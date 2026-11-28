import Foundation
import Combine
import Darwin
import CryptoKit

/// Executable allowlist. User prompts never become shell commands.
enum JarvisAgentID: String, CaseIterable, Identifiable {
    case claude, gemini, codex
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .gemini: "Gemini CLI"
        case .codex: "Codex"
        }
    }
}

struct JarvisAgentLane: Identifiable {
    enum State: String {
        case missing, checking, ready, running, completed, failed, cancelled
    }

    let id: JarvisAgentID
    var state: State = .checking
    var version = ""
    var logs: [String] = []
    var lastRun: UUID?
    var lastExitCode: Int32?
    var updatedAt: Date?

    var stateLabel: String {
        switch state {
        case .missing: "미설치"
        case .checking: "확인 중"
        case .ready: "대기"
        case .running: "RUNNING"
        case .completed: "완료"
        case .failed: "오류"
        case .cancelled: "중단됨"
        }
    }
}

struct JarvisKnowledgePilotRun: Codable, Identifiable {
    enum State: String, Codable { case running, artifactsReady, incomplete, failed, cancelled }
    static let artifactNames = ["article.md", "cover.png", "body-01.png", "report.md"]
    let id: UUID
    let directory: URL
    let startedAt: Date
    var state: State
    var finishedAt: Date?
    var exitCode: Int32?

    // This is the producing agent's self-review, not independent visual verification.
    func hasPassingImageReview() -> Bool {
        guard hasArtifact("report.md"),
              let report = try? String(contentsOf: directory.appendingPathComponent("report.md"), encoding: .utf8)
        else { return false }
        let lines = report.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let required = [
            "cover.png visual check: pass",
            "body-01.png explanatory check: pass",
            "final package status: ready"
        ]
        return required.allSatisfy { expected in
            let prefix = String(expected.split(separator: ":", maxSplits: 1)[0]) + ":"
            return lines.filter { $0.hasPrefix(prefix) } == [expected]
        }
    }

    struct SanityReceipt: Decodable {
        let id: String
        let slug: String
        let status: String
        let humanVerified: Bool
        let checkedAt: String
    }

    func sanityReceipt() -> SanityReceipt? {
        let file = directory.appendingPathComponent("sanity-stage.json")
        guard let v = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              v.isRegularFile == true, v.isSymbolicLink != true,
              let data = try? Data(contentsOf: file),
              let receipt = try? JSONDecoder().decode(SanityReceipt.self, from: data),
              receipt.id == "drafts.knowledge-" + receipt.slug,
              receipt.status == "review", !receipt.humanVerified else { return nil }
        return receipt
    }

    func hasArtifact(_ name: String) -> Bool {
        guard Self.artifactNames.contains(name) else { return false }
        let file = directory.appendingPathComponent(name)
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 30 else { return false }
        if name.hasSuffix(".png") {
            guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 8)) == Data([137, 80, 78, 71, 13, 10, 26, 10])
        }
        return true
    }
}

/// Owns actual CLI processes across dashboard open/close. Explicit user
/// requests and the owner-authorized nightly Knowledge shift may start work.
/// Probe uses --version. No shell, eval, or automatic publication approval.
@MainActor
final class JarvisAgentTerminalBay: ObservableObject {
    // Shared across full-screen, mini core, and app lifecycle; one worker owner.
    static let shared = JarvisAgentTerminalBay()
    private var nightSchedulerTask: Task<Void, Never>?

    func startNightScheduler() {
        guard nightSchedulerTask == nil else { return }
        nightSchedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.beginNightShiftIfDue()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        NSLog("JARVIS Knowledge scheduler active (KST 00:00-01:00; review only)")
    }

    func stopNightScheduler() {
        nightSchedulerTask?.cancel()
        nightSchedulerTask = nil
        if nightShiftRunning { cancel(.codex) }
    }

    @Published private(set) var lanes: [JarvisAgentLane] =
        JarvisAgentID.allCases.map { JarvisAgentLane(id: $0) }
    @Published private(set) var events: [String] = []
    @Published private(set) var knowledgePilot: JarvisKnowledgePilotRun?
    @Published private(set) var knowledgePilotError: String?
    private var pilotWatchdog: Task<Void, Never>?
    @Published private(set) var knowledgeBudgetRevision = 0
    var knowledgeDailyStarts: Int { JarvisKnowledgeDailyBudget.used() }
    var knowledgeDailyLimitReached: Bool { knowledgeDailyStarts >= JarvisKnowledgeDailyBudget.limit }
    var knowledgeDailyRepairs: Int { JarvisKnowledgeDailyBudget.repairUsed() }
    var knowledgeDailyStaged: Int { Set(JarvisKnowledgeDailyBudget.stagedToday()).count }

    @Published private(set) var nightShiftRunning = false
    @Published private(set) var nightShiftStatus = "자정 자동 근무 활성"
    @Published private(set) var nightShiftFinishedDay: String?
    private var nightShiftTask: Task<Void, Never>?
    private var nightStopRequested = false
    private var nightCheckedDay: String?
    private var nightDeadline: Date?
    @Published var stageAfterPilot = false
    @Published private(set) var sanityStageRunning = false
    @Published private(set) var sanityStageMessage: String?
    private var stageAfterPilotID: UUID?

    var canStageKnowledge: Bool {
        guard let run = knowledgePilot, run.state == .artifactsReady,
              !isAnyRunning, !sanityStageRunning else { return false }
        return JarvisKnowledgePilotRun.artifactNames.allSatisfy { run.hasArtifact($0) }
            && run.hasPassingImageReview()
    }

    /// Runs the deterministic CMS importer, not a model with CMS credentials.
    /// This is a review draft only; the site still requires human verification.
    func stageKnowledgePilot() {
        guard canStageKnowledge, let run = knowledgePilot, processes[.codex] == nil else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let site = home.appendingPathComponent("Documents/ChatGPT/Dechive Site", isDirectory: true)
        let node = home.appendingPathComponent(".nvm/versions/node/v24.7.0/bin/node").path
        let cli = site.appendingPathComponent("node_modules/.bin/sanity").path
        let script = site.appendingPathComponent("scripts/jarvis-knowledge-import.mjs").path
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: node), fm.fileExists(atPath: cli), fm.fileExists(atPath: script) else {
            sanityStageMessage = "Sanity CLI 또는 등록 스크립트를 찾지 못했습니다."
            return
        }
        sanityStageRunning = true
        sanityStageMessage = "Sanity 검토 등록 및 재조회 중"
        launch(.codex, executable: node,
               arguments: [cli, "exec", script, "--with-user-token", "--", "--run-dir", run.directory.path, "--mode", "stage"],
               isProbe: false, workingDirectory: site, sanityRunID: run.id)
    }

    private func finishSanityStage(id: UUID, code: Int32, aborted: Bool) {
        sanityStageRunning = false
        guard let run = knowledgePilot, run.id == id else {
            sanityStageMessage = "실행 기록이 변경되었습니다. Sanity에서 상태를 확인하세요."
            return
        }
        if !aborted && code == 0 && run.sanityReceipt() != nil {
            sanityStageMessage = "Sanity 검토 등록 · 재조회 확인 (미공개)"
        } else {
            sanityStageMessage = aborted ? "등록 중단 · CMS 상태 재확인 필요" :
                "등록 실패 또는 확인 누락 · 실제 로그 확인"
        }
        append(.codex, sanityStageMessage ?? "")
    }
    private static var pilotRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".jarvis-lab/knowledge-pilot", isDirectory: true)
    }

    var knowledgePilotLabel: String {
        switch knowledgePilot?.state {
        case nil: "시범 준비"
        case .running: nightShiftRunning ? "RUNNING / NIGHT SHIFT" : "RUNNING / PILOT"
        case .artifactsReady: "산출물 생성 · 검토 대기"
        case .incomplete: "산출물 / 자체 검수 미완료"
        case .failed: "실행 실패"
        case .cancelled: "중단"
        }
    }

    init() {
        let file = Self.pilotRoot.appendingPathComponent("latest-run.json")
        if let data = try? Data(contentsOf: file),
           var prior = try? JSONDecoder().decode(JarvisKnowledgePilotRun.self, from: data) {
            // Never assume a child process survived a previous app instance.
            if prior.state == .running {
                prior.state = .cancelled
                prior.finishedAt = Date()
            }
            knowledgePilot = prior
        }
    }

    private func savePilot() {
        guard let run = knowledgePilot, let data = try? JSONEncoder().encode(run) else { return }
        do {
            try data.write(to: Self.pilotRoot.appendingPathComponent("latest-run.json"), options: .atomic)
            try data.write(to: run.directory.appendingPathComponent("run-state.json"), options: .atomic)
        } catch {
            knowledgePilotError = "작업 기록 저장 실패: " + error.localizedDescription
        }
    }

    /// Explicit one-article rehearsal, not a recurring schedule or publishing
    /// job. The Codex CLI gets a fresh isolated workspace and no CMS token.
    func runKnowledgePilot() {
        guard !nightShiftRunning else { return }
        runKnowledgePilot(topic: nil)
    }

    private func runKnowledgePilot(topic: JarvisKnowledgeTopic?) {
        guard !isAnyRunning, processes[.codex] == nil, knowledgePilot?.state != .running else { return }
        knowledgePilotError = nil
        guard !knowledgeDailyLimitReached else {
            knowledgePilotError = "한국시간 오늘의 Knowledge 작업 3회 한도에 도달했습니다."
            return
        }
        let executable = "/opt/homebrew/bin/codex"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            knowledgePilotError = "검증한 Codex CLI 실행 파일이 없습니다."
            return
        }
        let fm = FileManager.default
        let root = Self.pilotRoot
        let reference = root.appendingPathComponent(topic == nil ? "reference" : "general-reference", isDirectory: true)
        for name in ["published-K03-05.json", "reference-cover.png", "reference-body-01.png",
                     "KNOWLEDGE_IMAGE_RULES.md", "KNOWLEDGE_BODY_IMAGE_RULES.md", "pilot-draft.md"] {
            guard fm.fileExists(atPath: reference.appendingPathComponent(name).path) else {
                knowledgePilotError = "검증한 참고 자료 누락: " + name
                return
            }
        }
        let runID = UUID()
        let directory = root.appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent((topic?.code ?? "K03-06") + "-" + runID.uuidString.lowercased(), isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.copyItem(at: reference, to: directory.appendingPathComponent("reference", isDirectory: true))
        } catch {
            knowledgePilotError = "시범 작업 폴더 준비 실패: " + error.localizedDescription
            return
        }
        let pilotPrompt = """
        DECHIVE.DEV Knowledge 야간 근무 시범 (한 편만, 실제 공개 금지).
        주제: K03-06 데이터 증강이란? / slug: what-is-data-augmentation / 카테고리: 03 데이터와 머신러닝.
        현재 작업 디렉터리 내부에서만 산출물을 작성한다. reference/published-K03-05.json은 실제 발행된 직전 글의 본문, 요약, 메타데이터 및 이미지 ALT/캡션이고 reference/reference-cover.png와 reference/reference-body-01.png는 기존 디자인 참고용이다. 먼저 확인하고 그 구조와 톤을 따른다. 기존 이미지를 복제하거나 다른 주제의 이미지로 대체하지 않는다.
        반드시 먼저 reference/KNOWLEDGE_IMAGE_RULES.md와 reference/KNOWLEDGE_BODY_IMAGE_RULES.md를 읽고 적용한다. 규칙 파일은 기존 참고 이미지의 분위기보다 우선하는 필수 제작 조건이다.
        reference/pilot-draft.md는 첫 시범에서 만든 원고다. 이번 재시험은 이미지 제작 기준 검증에 집중한다. 원고의 구조와 내용을 유지해 article.md로 복사하되, 새 이미지의 ALT·캡션·삽입 위치와 실제 일치하도록 필요한 부분만 수정한다. 명백한 사실 오류가 있으면 공식 출처 확인 후 보고서에 수정 이유를 기록한다.
        cover.png에는 좌측 상단 DECHIVE KNOWLEDGE, 굵은 흰색 제목 1행 '데이터 증강이란?', 2행 '같은 데이터를 다르게 보다', 작은 부제 '하나의 데이터로 어떻게 더 많이 배울까?', 우측 하단 흰색 필기체 DECHIVE가 반드시 실제 픽셀에 있어야 한다. 배경만 생성하면 불합격이다.
        body-01.png는 원본을 먼저 분할하고 학습 분할에만 증강을 적용하는 흐름을 한글 라벨로 보여준다. 독립 평가 경로에 같은 원본이나 변형을 재사용하지 않는다. 별개의 사진으로 표현하고 모델 학습과 연결하지 않는다.
        필수 산출물: article.md (완성된 한국어 원고, 제목/요약/slug/카테고리/keywords/대표 이미지 및 본문 이미지의 ALT와 캡션, 정확한 본문 삽입 위치, 출처 URL 포함), cover.png (기존 표지 디자인에 맞는 새 이미지), body-01.png (검증 가능한 교육용 본문 도식), report.md (실제 확인한 근거, 이미지 생성 및 검수 상태, 실패/누락, 추후 발행 체크리스트).
        설치된 이미지 생성 Skill과 내장 이미지 도구를 사용한다. 불가능하면 보고한다. 별도 유료 API, API 키 탐색, 우회 인증, 기존 이미지 복제, 가짜 PNG는 금지한다. 생성한 최종 PNG 두 개를 실제 이미지 보기 도구로 열어 검사한다. 표지 축소 미리보기의 가독성도 확인한다. 누락 또는 잘못된 표현은 최대 한 차례 수정 후 재검사한다.
        report.md에 각 필수 텍스트와 도식 흐름의 확인 근거를 적고, 아래 세 판정 줄을 각각 정확히 한 번, 마크다운 장식 없이 독립된 줄로 기록한다. 실제 확인이 불가능하거나 위반이 남으면 pass 대신 fail, ready 대신 incomplete를 기록한다.
        cover.png visual check: pass
        body-01.png explanatory check: pass
        final package status: ready
        위 문자열은 통과한 경우의 형식 예시일 뿐이다. 실패해도 pass라고 쓰지 않는다. 이 결과는 AI 자체 검수이며 독립 검증이나 사람 검수로 표시하지 않는다.
        현재는 자정 근무를 가정한 단일 테스트이며 실제 사이트, CMS, Sanity, Git, 배포, 다른 폴더, 인증 설정, humanVerified에는 어떠한 변경도 하지 않는다. 비밀 키나 토큰을 읽거나 출력하지 않는다. shell 네트워크를 활성화하거나 권한 상승을 요청하지 않는다. 내장 검색은 공식 출처 확인에만 사용한다.
        이번에는 한 편만 만든다. 모든 작업은 산출물 폴더 안에 남기고, 실제 결과가 없으면 성공으로 보고하지 않는다. 이미지 도구가 없으면 원고와 실패 보고까지만 완성하고 무한 재시도하지 않는다.
        """
        let prompt: String
        if let topic {
            prompt = """
            DECHIVE.DEV Knowledge 정규 집필. 한 편만 제작. 실제 공개 금지.
            주제 번호: \(topic.number) / 코드: \(topic.code) / 제목 주제: \(topic.title)
            고정 slug: \(topic.resolvedSlug) / category: \(topic.category)
            현재 작업 폴더 안에서만 새 원고와 이미지 작성. job.json의 주제, slug, category를 변경하지 않는다.
            reference/KNOWLEDGE_IMAGE_RULES.md와 reference/KNOWLEDGE_BODY_IMAGE_RULES.md를 반드시 읽고 따른다. reference/pilot-draft.md는 YAML 및 마크다운 구조의 예시이며 내용은 복제하지 않는다. reference/published-K03-05.json 및 두 PNG는 문체와 디자인 참고용이다.
            주제 하나에 답하는 독립적인 한국어 원고. 공식 1차 자료를 실제 검색하고 열람하여 주장별 근거를 확인한다. 정확한 정의, 예시, 혼동하기 쉬운 개념과 한계, 검증 기준을 설명한다. 출처를 지어내지 않는다.
            필수 산출물: article.md, cover.png, body-01.png, report.md. article.md는 예시와 동일한 YAML 구조(title 100자 이내, summary 20~240자, 고정 slug/category, keywords 최대 8개, cover.file/alt/caption, body_images 한 항목 file/alt/caption/insert_location). h2/h3, 일반 문단, 단일 단계 목록, 일반 텍스트 마크다운 표, HTTPS 링크와 [^id] 각주를 사용한다. 각주 정의는 한 줄에 공식 HTTPS 링크 하나. 본문 이미지 마크다운 ALT와 바로 아래 이탤릭 캡션은 YAML의 값과 정확히 일치해야 한다. 별도 HTML, 코드 블록, 중첩 목록, 복잡한 표는 사용하지 않는다.
            이미지 두 개 모두 1672×941 PNG. 표지는 고정 브랜드와 주제별 제목·부제·서명, 기존 남색 서재와 황동 조명을 유지한다. 본문 도식은 해당 주제만 설명하고, 실제 관계와 가독성을 검수한다. 정확한 한글 조판은 Swift/AppKit으로 처리 가능. 내장 이미지 생성 Skill을 사용하고 별도 유료 API, 키 탐색, 기존 이미지 복제는 금지. 생성 후 실제 이미지 보기 도구로 열고 축소 검수한다. 핵심 단계명은 400px 모바일 폭을 먼저 고려해 원본 약 58~67px 이상을 우선 검토한다. 문구와 배치를 간결하게 만들고 실제 축소본에서 확인한다. 규칙 위반은 최대 한 차례 수정 후 재확인.
            report.md에는 실제 출처와 검증 근거, 이미지 확인 결과, 결함을 기록한다. 다음 세 줄을 독립된 줄로 정확히 한 번 기록하되 실패하면 pass 대신 fail, ready 대신 incomplete로 기록한다.
            cover.png visual check: pass
            body-01.png explanatory check: pass
            final package status: ready
            위 판정은 AI 자체 검수일 뿐 사람 검증이 아니다. 사이트/CMS/Git/배포/인증 설정/humanVerified 변경, 작업 폴더 외부 수정, 권한 상승, 비밀 키 조회는 금지한다. shell 네트워크 사용 금지. 작업이 불가능하면 실패 이유를 저장하고 멈춘다.
            """
        } else { prompt = pilotPrompt }
        do {
            if let topic {
                let manifest = ["code": topic.code, "title": topic.title, "slug": topic.resolvedSlug, "category": topic.category]
                try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("job.json"), options: .atomic)
            }
            try prompt.write(to: directory.appendingPathComponent("task.md"), atomically: true, encoding: .utf8)
        } catch {
            knowledgePilotError = "작업 지시서 저장 실패: " + error.localizedDescription
            return
        }
        // Consume the daily slot before launching the model, including failed
        // attempts. Fail closed if the local budget cannot be persisted.
        do {
            guard try JarvisKnowledgeDailyBudget.reserve() != nil else {
                knowledgePilotError = "한국시간 오늘의 Knowledge 작업 3회 한도에 도달했습니다."
                return
            }
            knowledgeBudgetRevision += 1
        } catch {
            knowledgePilotError = "일일 작업 한도 기록 실패 · 실행 중단"
            return
        }
        knowledgePilot = JarvisKnowledgePilotRun(id: runID, directory: directory, startedAt: Date(), state: .running)
        sanityStageMessage = nil
        stageAfterPilotID = topic == nil && stageAfterPilot ? runID : nil
        savePilot()
        let arguments = ["--search", "-a", "never", "exec", "-m", "gpt-5.6-terra",
                         "--sandbox", "workspace-write", "-c", "sandbox_workspace_write.network_access=false",
                         "--ephemeral", "--skip-git-repo-check", "--json", "-C", directory.path,
                         "-o", directory.appendingPathComponent("result.md").path, prompt]
        launch(.codex, executable: executable, arguments: arguments, isProbe: false,
               workingDirectory: directory, pilotID: runID)
        if knowledgePilot?.state == .running {
            pilotWatchdog?.cancel()
            pilotWatchdog = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
                guard let self, self.knowledgePilot?.id == runID,
                      self.knowledgePilot?.state == .running else { return }
                self.knowledgePilotError = "개별 작업 60분 제한 도달 · 실행 중단"
                self.cancel(.codex)
            }
        }
    }

    private func finishKnowledgePilot(id: UUID, code: Int32, aborted: Bool) {
        guard var run = knowledgePilot, run.id == id else { return }
        pilotWatchdog?.cancel()
        pilotWatchdog = nil
        run.finishedAt = Date()
        run.exitCode = code
        let filesComplete = JarvisKnowledgePilotRun.artifactNames.allSatisfy { run.hasArtifact($0) }
        let protected = repairProtectedDigests.removeValue(forKey: id)
        let repairPreserved = protected?.allSatisfy { name, digest in
            let file = run.directory.appendingPathComponent(name)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: file) else { return false }
            return name == "body-01.png" ? Self.repairDigest(data) != digest : Self.repairDigest(data) == digest
        } ?? true
        let reviewPassed = filesComplete && run.hasPassingImageReview() && repairPreserved
        run.state = aborted ? .cancelled : code != 0 ? .failed : reviewPassed ? .artifactsReady : .incomplete
        knowledgePilot = run
        if !repairPreserved {
            knowledgePilotError = "복구 무결성 실패 · 원고/표지/주제 변경 또는 본문 이미지 미수정 · 검토 등록 금지"
        } else if !aborted && code == 0 && !filesComplete {
            knowledgePilotError = "누락 또는 형식 불일치: " + JarvisKnowledgePilotRun.artifactNames.filter { !run.hasArtifact($0) }.joined(separator: ", ")
        } else if !aborted && code == 0 && !reviewPassed {
            knowledgePilotError = "이미지 자체 검수 실패 또는 판정 누락 · report.md 확인"
        }
        append(.codex, "Knowledge 시범 종료 · " + knowledgePilotLabel)
        savePilot()
        // Only after a successful, non-cancelled worker exit. Failed or
        // interrupted runs are left intact for troubleshooting.
        if !aborted && code == 0 {
            do {
                let removed = try JarvisKnowledgeRunMaintenance.clean(
                    runDirectory: run.directory,
                    runsRoot: Self.pilotRoot.appendingPathComponent("runs", isDirectory: true))
                if removed.files > 0 {
                    append(.codex, "임시 컴파일 캐시 정리 · " + String(removed.files) + "개 · " +
                           ByteCountFormatter.string(fromByteCount: Int64(removed.bytes), countStyle: .file))
                }
            } catch {
                append(.codex, "임시 캐시 정리 보류 · 안전 조건 확인 필요")
            }
        }
        let shouldStage = stageAfterPilotID == id
        stageAfterPilotID = nil
        if shouldStage && run.state == .artifactsReady {
            stageKnowledgePilot()
        }
    }


    /// App-lifetime midnight trigger. The same worker serves every UI surface.
    func beginNightShiftIfDue() {
        let now = Date()
        guard !nightShiftRunning, let deadline = JarvisKnowledgeNightPolicy.deadline(at: now),
              JarvisKnowledgeNightPolicy.mayStart(at: now, deadline: deadline) else { return }
        let day = JarvisKnowledgeDailyBudget.dayKey(at: now)
        guard nightCheckedDay != day, !isAnyRunning, processes[.codex] == nil else { return }
        nightCheckedDay = day
        do {
            guard let folder = try JarvisKnowledgeNightPolicy.claim(root: Self.pilotRoot, day: day) else {
                let existing = Self.pilotRoot.appendingPathComponent("night-shifts").appendingPathComponent(day)
                let request = existing.appendingPathComponent("resume-request.json")
                if FileManager.default.fileExists(atPath: existing.appendingPathComponent("recovery.lock").path)
                   || !JarvisKnowledgeDailyBudget.usesSeparateRepairs(at: now) {
                    if let data = try? Data(contentsOf: existing.appendingPathComponent("summary.json")),
                       let summary = try? JSONDecoder().decode([String: String].self, from: data),
                       let reason = summary["reason"] {
                        nightShiftStatus = reason
                    } else { nightShiftStatus = "오늘 근무 기록 있음 · 중복 실행 방지" }
                    return
                }
                guard let data = try? Data(contentsOf: request),
                      let approval = try? JSONDecoder().decode([String: String].self, from: data),
                      approval["day"] == day, approval["reason"] == "owner-requested-image-repair",
                      let summaryData = try? Data(contentsOf: existing.appendingPathComponent("summary.json")),
                      let summary = try? JSONDecoder().decode([String: String].self, from: summaryData),
                      summary["day"] == day, summary["reason"] == "제작 미완료 · 다음 근무에서 재검토",
                      let code = approval["code"], summary["attempted"]?.split(separator: ",").last.map(String.init) == code,
                      let catalog = try? JarvisKnowledgeCatalog.load(),
                      let topic = catalog.topics.first(where: { $0.code == code }),
                      repairCandidate(for: topic) != nil, !knowledgeDailyLimitReached else {
                    nightShiftStatus = "오늘 근무 기록 있음 · 중복 실행 방지"
                    return
                }
                let fd = Darwin.open(existing.appendingPathComponent("recovery.lock").path,
                                     O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
                guard fd >= 0 else { nightShiftStatus = "오늘 복구 요청 이미 처리됨"; return }
                Darwin.close(fd)
                try summaryData.write(to: existing.appendingPathComponent("summary-before-recovery.json"), options: .withoutOverwriting)
                nightShiftRunning = true
                nightStopRequested = false
                nightDeadline = deadline
                nightShiftTask = Task { [weak self] in
                    await self?.executeNightShift(day: day, folder: existing, deadline: deadline,
                        priorAttempted: (summary["attempted"] ?? "").split(separator: ",").map(String.init),
                        priorStaged: (summary["staged"] ?? "").split(separator: ",").map(String.init),
                        resumedTopic: code)
                }
                return
            }
            nightShiftRunning = true
            nightStopRequested = false
            nightDeadline = deadline
            nightShiftTask = Task { [weak self] in
                await self?.executeNightShift(day: day, folder: folder, deadline: deadline)
            }
        } catch { nightShiftStatus = "근무 기록 생성 실패 · 자동 실행 중지" }
    }

    private func waitForNightWorker(deadline: Date) async -> Bool {
        while processes[.codex] != nil {
            if Date() >= deadline || nightStopRequested {
                if let process = processes[.codex], process.isRunning {
                    process.terminate()
                    // Give termination a short grace period; never start
                    // another process while the previous one is still tracked.
                    try? await Task.sleep(for: .seconds(3))
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                return false
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return false }
        }
        return Date() < deadline && !nightStopRequested
    }

    private func refreshNightInventory(folder: URL, deadline: Date) async -> JarvisKnowledgeInventory? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let site = home.appendingPathComponent("Documents/ChatGPT/Dechive Site", isDirectory: true)
        let node = home.appendingPathComponent(".nvm/versions/node/v24.7.0/bin/node").path
        let cli = site.appendingPathComponent("node_modules/.bin/sanity").path
        let script = site.appendingPathComponent("scripts/jarvis-knowledge-inventory.mjs").path
        let file = folder.appendingPathComponent("inventory.json")
        guard FileManager.default.isExecutableFile(atPath: node),
              FileManager.default.fileExists(atPath: script),
              FileManager.default.fileExists(atPath: cli),
              processes[.codex] == nil, !isAnyRunning else { return nil }
        if FileManager.default.fileExists(atPath: file.path) {
            do { try FileManager.default.removeItem(at: file) } catch { return nil }
        }
        launch(.codex, executable: node, arguments: [cli, "exec", script, "--with-user-token", "--", "--output", file.path],
               isProbe: false, workingDirectory: site)
        guard await waitForNightWorker(deadline: deadline), lane(.codex).lastExitCode == 0,
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(JarvisKnowledgeInventory.self, from: data)
    }

    private func reusableNightPackage(for topic: JarvisKnowledgeTopic) -> JarvisKnowledgePilotRun? {
        let root = Self.pilotRoot.appendingPathComponent("runs", isDirectory: true)
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        return folders.compactMap { folder -> JarvisKnowledgePilotRun? in
            guard folder.lastPathComponent.hasPrefix(topic.code + "-"),
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("run-state.json")),
                  let run = try? JSONDecoder().decode(JarvisKnowledgePilotRun.self, from: data),
                  run.directory.standardizedFileURL.path == folder.standardizedFileURL.path,
                  run.state == .artifactsReady, run.sanityReceipt() == nil,
                  let manifestData = try? Data(contentsOf: folder.appendingPathComponent("job.json")),
                  let job = try? JSONDecoder().decode([String: String].self, from: manifestData),
                  job["code"] == topic.code, job["slug"] == topic.resolvedSlug,
                  job["title"] == topic.title, job["category"] == topic.category,
                  JarvisKnowledgePilotRun.artifactNames.allSatisfy({ run.hasArtifact($0) }),
                  run.hasPassingImageReview() else { return nil }
            return run
        }.max(by: { $0.startedAt < $1.startedAt })
    }


    private func repairCandidate(for topic: JarvisKnowledgeTopic) -> JarvisKnowledgePilotRun? {
        let root = Self.pilotRoot.appendingPathComponent("runs", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        return folders.compactMap { folder -> JarvisKnowledgePilotRun? in
            guard folder.lastPathComponent.hasPrefix(topic.code + "-"),
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("run-state.json")),
                  let run = try? JSONDecoder().decode(JarvisKnowledgePilotRun.self, from: data),
                  run.directory.standardizedFileURL.path == folder.standardizedFileURL.path,
                  run.state == .incomplete, run.sanityReceipt() == nil,
                  !FileManager.default.fileExists(atPath: folder.appendingPathComponent("repair-origin.json").path),
                  let manifest = try? Data(contentsOf: folder.appendingPathComponent("job.json")),
                  let job = try? JSONDecoder().decode([String: String].self, from: manifest),
                  job["code"] == topic.code, job["slug"] == topic.resolvedSlug,
                  job["title"] == topic.title, job["category"] == topic.category,
                  JarvisKnowledgePilotRun.artifactNames.allSatisfy({ run.hasArtifact($0) }),
                  let report = try? String(contentsOf: folder.appendingPathComponent("report.md"), encoding: .utf8),
                  report.components(separatedBy: .newlines).contains("cover.png visual check: pass"),
                  report.components(separatedBy: .newlines).contains("body-01.png explanatory check: fail"),
                  report.components(separatedBy: .newlines).contains("final package status: incomplete")
            else { return nil }
            return run
        }.max(by: { $0.startedAt < $1.startedAt })
    }

    private func repairKnowledgePilot(_ source: JarvisKnowledgePilotRun, topic: JarvisKnowledgeTopic) -> Bool {
        guard !isAnyRunning, processes[.codex] == nil,
              JarvisKnowledgeDailyBudget.usesSeparateRepairs() else { return false }
        let fm = FileManager.default
        let executable = "/opt/homebrew/bin/codex"
        guard fm.isExecutableFile(atPath: executable) else { return false }
        let id = UUID()
        let directory = Self.pilotRoot.appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(topic.code + "-" + id.uuidString.lowercased(), isDirectory: true)
        let prompt = """
        DECHIVE Knowledge 기존 미완료 산출물의 제한적 복구 작업. 실제 공개 금지.
        대상: \(topic.code) / \(topic.title). 기존 원고 article.md 및 통과한 cover.png, job.json은 바이트 단위로 변경 금지.
        report.md와 reference의 제작 규칙을 먼저 읽고 실패한 body-01.png만 개선한다. 원본 파일은 별도 이전 실행 폴더에 보존되어 있다.
        기존 도식의 의미, ALT, 캡션, 삽입 위치를 유지한다. 한글 핵심 단계명은 400px에서 읽히도록 원본 기준 약 58~67px 이상의 글꼴을 우선 고려하고 문구와 상자 배치를 단순화한다. 수치 자체가 통과를 보장하지 않는다.
        처음부터 400px 폭을 기준으로 설계하고 1672×941 최종 PNG를 만든다. 기존 body-base.png와 compose.swift가 있으면 참고하되 표지 파일을 다시 쓰지 않는다. 필요하면 상자·선·라벨을 같은 좌표계에서 직접 그린다.
        실제 원본, 800px, 400px 이미지를 이미지 보기 도구로 열어 모든 필수 단계명, 겹침, 대비, 정확성 및 원고 일치를 확인한다. 이번 복구 작업에 한해서만 참고 규칙의 일반 제작 1회 수정 제한에 예외로 최대 두 차례 수정 후 재검사할 수 있다. 기준 완화 금지.
        report.md의 기존 출처와 검수 근거를 보존하고 이번 수정과 실제 검사 결과를 추가한다. 세 판정 줄은 각각 정확히 한 번만 남긴다. 모든 조건을 실제 확인한 경우에만 아래 형식을 사용한다.
        cover.png visual check: pass
        body-01.png explanatory check: pass
        final package status: ready
        실패가 남거나 실제 시각 확인이 불가능하면 fail / incomplete를 그대로 기록한다. AI 자체 검수이며 사람 독립 검증이 아니다.
        작업 폴더 밖 수정, 사이트/CMS/Git/배포/인증 설정 변경, 비밀 키 조회, 별도 유료 API 및 권한 상승 금지. 실제 공개 금지.
        """
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for name in ["article.md","cover.png","body-01.png","report.md","job.json","reference"] {
                try fm.copyItem(at: source.directory.appendingPathComponent(name), to: directory.appendingPathComponent(name))
            }
            for name in ["body-base.png","compose.swift"] {
                let file = source.directory.appendingPathComponent(name)
                if let v = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), v.isRegularFile == true, v.isSymbolicLink != true {
                    try fm.copyItem(at: file, to: directory.appendingPathComponent(name))
                }
            }
            let protected = try Dictionary(uniqueKeysWithValues: ["article.md","cover.png","job.json","body-01.png"].map { name in
                (name, Self.repairDigest(try Data(contentsOf: directory.appendingPathComponent(name))))
            })
            let metadata = ["sourceID":source.id.uuidString, "article.md":protected["article.md"]!,
                            "cover.png":protected["cover.png"]!, "job.json":protected["job.json"]!, "body-01.png":protected["body-01.png"]!]
            try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("repair-origin.json"), options: .atomic)
            try prompt.write(to: directory.appendingPathComponent("task.md"), atomically: true, encoding: .utf8)
            guard try JarvisKnowledgeDailyBudget.reserveRepair(topicCode: topic.code) else {
                knowledgePilotError = "복구 한도 도달 또는 오늘 이미 해당 주제 복구 실행"
                return false
            }
            knowledgeBudgetRevision += 1
            repairProtectedDigests[id] = protected
        } catch {
            knowledgePilotError = "복구 작업 준비 실패 · 원본 보존"
            return false
        }
        knowledgePilot = JarvisKnowledgePilotRun(id: id, directory: directory, startedAt: Date(), state: .running)
        knowledgePilotError = nil
        sanityStageMessage = nil
        stageAfterPilotID = nil
        savePilot()
        let arguments = ["--search", "-a", "never", "exec", "-m", "gpt-5.6-terra",
                         "--sandbox", "workspace-write", "-c", "sandbox_workspace_write.network_access=false",
                         "--ephemeral", "--skip-git-repo-check", "--json", "-C", directory.path,
                         "-o", directory.appendingPathComponent("result.md").path, prompt]
        launch(.codex, executable: executable, arguments: arguments, isProbe: false, workingDirectory: directory, pilotID: id)
        return processes[.codex] != nil
    }

    private var repairProtectedDigests: [UUID: [String: String]] = [:]
    private static func repairDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func executeNightShift(day: String, folder: URL, deadline: Date,
                                   priorAttempted: [String] = [], priorStaged: [String] = [],
                                   resumedTopic: String? = nil) async {
        var staged = priorStaged
        var reason = "근무 시간 / 작업 한도 종료"
        var attempted = priorAttempted
        var recoveryTopic = resumedTopic
        defer {
            nightShiftRunning = false
            nightDeadline = nil
            nightShiftTask = nil
            nightShiftStatus = reason
            let report = ["day": day, "finishedAt": ISO8601DateFormatter().string(from: Date()),
                          "staged": staged.joined(separator: ","), "attempted": attempted.joined(separator: ","),
                          "reason": reason, "starts": String(knowledgeDailyStarts),
                          "repairs": String(knowledgeDailyRepairs)]
            do {
                try JSONEncoder().encode(report).write(to: folder.appendingPathComponent("summary.json"), options: .atomic)
            } catch { nightShiftStatus += " · 보고서 저장 실패" }
            record("Knowledge 야간 근무 종료 · " + reason)
            nightShiftFinishedDay = day
        }
        guard let catalog = try? JarvisKnowledgeCatalog.load() else { reason = "집필 목록 확인 실패"; return }
        while !nightStopRequested && staged.count < JarvisKnowledgeDailyBudget.limit &&
                attempted.count < JarvisKnowledgeDailyBudget.limit &&
                JarvisKnowledgeNightPolicy.mayStart(at: Date(), deadline: deadline) {
            nightShiftStatus = "Sanity 공개·초안 목록 확인 중"
            guard let inventory = await refreshNightInventory(folder: folder, deadline: deadline) else {
                reason = "Sanity 현황 확인 실패 또는 근무 중단"; return
            }
            let topic: JarvisKnowledgeTopic
            do {
                guard let next = try inventory.next(in: catalog) else { reason = "집필 대상 없음"; return }
                topic = next
            } catch { reason = "CMS 미매핑 문서 또는 카테고리 확인 필요"; return }
            guard (recoveryTopic == nil || recoveryTopic == topic.code),
                  (!attempted.contains(topic.code) || recoveryTopic == topic.code),
                  JarvisKnowledgeNightPolicy.mayStart(at: Date(), deadline: deadline), !nightStopRequested else {
                reason = "중복 또는 남은 근무 시간 부족"; return
            }
            nightShiftStatus = topic.code + " · 집필 중"
            if !attempted.contains(topic.code) { attempted.append(topic.code) }
            recoveryTopic = nil
            if let reusable = reusableNightPackage(for: topic) {
                knowledgePilot = reusable
                knowledgePilotError = nil
                savePilot()
                nightShiftStatus = topic.code + " · 기존 완성 산출물 재사용"
            } else if let source = repairCandidate(for: topic) {
                nightShiftStatus = topic.code + " · 기존 본문 이미지 복구"
                guard repairKnowledgePilot(source, topic: topic),
                      await waitForNightWorker(deadline: deadline),
                      knowledgePilot?.state == .artifactsReady else {
                    reason = "복구 검수 미통과 · 원본 보존"; return
                }
            } else {
                guard !knowledgeDailyLimitReached else {
                    reason = "신규 집필 3회 한도 도달 · 미승인 글 보존"; return
                }
                let previous = knowledgePilot?.id
                runKnowledgePilot(topic: topic)
                guard let run = knowledgePilot, run.id != previous,
                      run.directory.lastPathComponent.hasPrefix(topic.code + "-") else {
                    reason = knowledgePilotError ?? "제작 실행 실패"; return
                }
                guard await waitForNightWorker(deadline: deadline), knowledgePilot?.id == run.id else {
                    reason = "제작 미완료 · 다음 근무에서 재검토"; return
                }
                if knowledgePilot?.state != .artifactsReady {
                    guard !nightStopRequested,
                          JarvisKnowledgeNightPolicy.mayStart(at: Date(), deadline: deadline),
                          let source = repairCandidate(for: topic), source.id == run.id else {
                        reason = "제작 미완료 · 다음 근무에서 재검토"; return
                    }
                    nightShiftStatus = topic.code + " · 본문 이미지 복구"
                    guard repairKnowledgePilot(source, topic: topic),
                          await waitForNightWorker(deadline: deadline),
                          knowledgePilot?.state == .artifactsReady else {
                        reason = "복구 검수 미통과 · 원본 보존"; return
                    }
                }
            }
            guard !nightStopRequested, Date() < deadline else { reason = "근무 종료 · 로컬 산출물 보존"; return }
            nightShiftStatus = topic.code + " · Sanity 검토 등록"
            stageKnowledgePilot()
            guard await waitForNightWorker(deadline: deadline),
                  lane(.codex).lastExitCode == 0,
                  knowledgePilot?.sanityReceipt()?.slug == topic.resolvedSlug else {
                reason = "검토 등록 실패 · 원본 보존"; return
            }
            staged.append(topic.code)
            let progress: [String: [String]] = ["day": [day], "staged": staged, "attempted": attempted]
            do {
                try JSONSerialization.data(withJSONObject: progress, options: [.sortedKeys])
                    .write(to: folder.appendingPathComponent("progress.json"), options: .atomic)
            } catch { reason = "진행 기록 저장 실패"; return }
            nightShiftStatus = topic.code + " · 승인 대기"
        }
        if nightStopRequested { reason = "사용자 중단" }
        else if staged.count >= JarvisKnowledgeDailyBudget.limit { reason = "검토 등록 3편 목표 달성 · 승인 대기" }
        else if knowledgeDailyLimitReached { reason = "신규 집필 3회 한도 도달 · 미승인 글 보존" }
    }

    private var processes: [JarvisAgentID: Process] = [:]
    private var executablePaths: [JarvisAgentID: String] = [:]
    private var partialLines: [JarvisAgentID: String] = [:]
    private var runKinds: [JarvisAgentID: Bool] = [:]
    private let workspace = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/JARVIS-FULLSCREEN-PREVIEW")

    var isAnyRunning: Bool { processes.values.contains { $0.isRunning } }

    /// P2 C2: CLI별 마지막 사용 한도 도달 (시각, 다시 쓸 수 있는 시각 등 출력 한 줄)
    @Published private(set) var limitHits: [JarvisAgentID: (at: Date, detail: String)] = [:]

    /// 출력에서 사용 한도 메시지를 찾는다. 찾으면 그 줄의 짧은 요약(없으면 "")을, 없으면 nil.
    nonisolated static func limitMessage<S: Sequence>(in lines: S) -> String? where S.Element == String {
        let patterns = ["usage limit", "rate limit", "limit reached", "hit your limit", "reached your limit",
                        "quota exceeded", "resource_exhausted", "too many requests", "status 429", "\"429\"",
                        "try again at", "resets at", "사용 한도", "사용량 한도"]
        for line in lines.reversed() {
            let lower = line.lowercased()
            guard patterns.contains(where: { lower.contains($0) }) else { continue }
            if let r = lower.range(of: #"(resets?|try again)( at| in)? [^\.\"]{1,40}"#, options: .regularExpression) {
                return String(lower[r]).trimmingCharacters(in: .whitespaces)
            }
            return ""
        }
        return nil
    }

    func lane(_ id: JarvisAgentID) -> JarvisAgentLane {
        lanes.first { $0.id == id } ?? JarvisAgentLane(id: id, state: .missing)
    }

    func probeAll(force: Bool = false) {
        for id in JarvisAgentID.allCases where processes[id] == nil {
            if !force && lanes.contains(where: { $0.id == id && $0.lastRun != nil }) {
                continue
            }
            guard let path = executable(for: id) else {
                update(id) {
                    $0.state = .missing
                    $0.logs = ["설치된 실행 파일을 찾지 못했습니다."]
                    $0.updatedAt = Date()
                }
                continue
            }
            executablePaths[id] = path
            launch(id, executable: path, arguments: ["--version"], isProbe: true)
        }
    }

    /// 실행하지 못하면 이유를 돌려주고 작업 패널 기록에도 남긴다 (예전에는 아무 말 없이 무시됐다).
    @discardableResult
    func runReadOnly(_ id: JarvisAgentID, prompt: String) -> String? {
        func refuse(_ reason: String) -> String {
            append(id, "실행 안 함 · " + reason)
            record(id.title + " · " + reason)
            return reason
        }
        guard !nightShiftRunning else { return refuse("밤 지식 작업이 도는 중이라 끝난 뒤에 맡길 수 있어요.") }
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return refuse("요청 내용이 비어 있어요.") }
        guard question.count <= 500 else { return refuse("요청이 500자를 넘어요. 짧게 줄여 주세요.") }
        guard !question.unicodeScalars.contains(where: { $0.value == 0 }) else { return refuse("요청에 읽을 수 없는 문자가 있어요.") }
        // P2 C3: CLI별로 하나씩. Claude가 도는 중이어도 Codex·Gemini에는 맡길 수 있다.
        guard processes[id] == nil else {
            return refuse("\(id.title) 작업이 아직 도는 중이에요. 끝나면 알려드릴게요.")
        }
        // P2 C2: 최근 사용 한도에 걸린 CLI는 바로 다시 보내지 않는다.
        if let hit = limitHits[id], Date().timeIntervalSince(hit.at) < 30 * 60 {
            let others = JarvisAgentID.allCases.filter { $0 != id && limitHits[$0] == nil }.map(\.title)
            return refuse("\(id.title) 사용 한도에 걸려 있어요" + (hit.detail.isEmpty ? "" : " (\(hit.detail))") +
                          (others.isEmpty ? "." : ". \(others.joined(separator: "나 "))에 맡겨 보세요."))
        }
        guard let path = executablePaths[id] ?? executable(for: id) else {
            update(id) { $0.state = .missing }
            return refuse("\(id.title) 실행 파일을 찾지 못했어요.")
        }
        // Model execution is explicit, limited to an existing project,
        // and guarded by the CLI's own read-only / plan permissions.
        let task = "읽기 전용 분석만 수행하세요. 파일을 변경하거나 배포, 게시, 결제, 커밋을 하지 마세요. 확인되지 않은 사실은 확인되지 않았다고 적으세요. 요청: " + question
        let arguments: [String]
        switch id {
        case .claude:
            arguments = ["-p", task, "--permission-mode", "plan",
                         "--allowedTools", "Read,Glob,Grep", "--max-turns", "3",
                         "--output-format", "stream-json", "--verbose",
                         "--no-session-persistence"]
        case .gemini:
            arguments = ["--prompt", task, "--approval-mode", "plan",
                         "--output-format", "stream-json"]
        case .codex:
            arguments = ["exec", "-C", workspace.path, "--sandbox", "read-only",
                         "--skip-git-repo-check", "--json", task]
        }
        launch(id, executable: path, arguments: arguments, isProbe: false)
        return nil
    }

    func cancel(_ id: JarvisAgentID) {
        if id == .codex && nightShiftRunning { nightStopRequested = true }
        guard let process = processes[id], process.isRunning else { return }
        append(id, "사용자가 작업 중단을 요청했습니다.")
        process.terminate()
    }

    private func executable(for id: JarvisAgentID) -> String? {
        let name = id.rawValue
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let nodeVersions = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: nodeVersions, includingPropertiesForKeys: nil) {
            directories.insert(contentsOf: versions.sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
            }.map { $0.appendingPathComponent("bin").path }, at: 0)
        }
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        directories.append(contentsOf: environmentPaths)
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func update(_ id: JarvisAgentID, edit: (inout JarvisAgentLane) -> Void) {
        guard let index = lanes.firstIndex(where: { $0.id == id }) else { return }
        edit(&lanes[index])
    }

    private func record(_ message: String) {
        events.append(Date().formatted(date: .omitted, time: .standard) + "  " + message)
        if events.count > 60 { events.removeFirst(events.count - 60) }
    }

    private func append(_ id: JarvisAgentID, _ message: String) {
        let clean = message.replacingOccurrences(
            of: #"(?:\u001B\[[0-9;]*[A-Za-z])"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let limited = String(clean.prefix(650))
        update(id) {
            $0.logs.append(limited)
            if $0.logs.count > 90 { $0.logs.removeFirst($0.logs.count - 90) }
            $0.updatedAt = Date()
        }
        if runKinds[id] != true {
            record(id.title + " · " + String(limited.prefix(100)))
        }
    }

    private func readableLine(_ line: String) -> String {
        guard line.first == "{",
              let data = line.data(using: .utf8),
              let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = item["type"] as? String else { return line }
        // Claude Code 시스템 이벤트(훅 실행 등)는 내용 없이 "[system]"만 반복되어
        // 에이전트 칸을 가득 채웠다. 세션 시작(init)만 한 줄로 보이고 나머지는 숨긴다.
        // (빈 문자열은 append()에서 버려진다.)
        if type == "system" {
            guard item["subtype"] as? String == "init" else { return "" }
            let model = item["model"] as? String ?? ""
            return "[system] 세션 시작" + (model.isEmpty ? "" : " · " + model)
        }
        // Errors must show the provider's own message rather than an empty
        // "[error]" tag. Never invent completion state from log shape.
        if let errorMessage = item["message"] as? String, !errorMessage.isEmpty {
            return "[" + type + "] " + errorMessage
        }
        // These are labels based on real streamed CLI JSON events, not
        // inferred progress percentages or invented tool completions.
        if let message = item["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let texts = content.compactMap { $0["text"] as? String }
            if !texts.isEmpty { return "[" + type + "] " + texts.joined(separator: " ") }
            let names = content.compactMap { $0["name"] as? String }
            if !names.isEmpty { return "[" + type + "] 도구: " + names.joined(separator: ", ") }
        }
        if let body = item["content"] as? String, !body.isEmpty { return "[" + type + "] " + body }
        if let detail = item["item"] as? [String: Any] {
            let kind = detail["type"] as? String ?? "item"
            let detailText = detail["text"] as? String ??
                detail["message"] as? String ?? detail["command"] as? String ?? ""
            return "[" + type + "/" + kind + "] " + detailText
        }
        if let result = item["result"] as? String, !result.isEmpty {
            return "[" + type + "] " + result
        }
        return "[" + type + "]"
    }

    private func receive(_ id: JarvisAgentID, data: Data) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        let combined = (partialLines[id] ?? "") + chunk
        let lines = combined.components(separatedBy: .newlines)
        partialLines[id] = String((lines.last ?? "").prefix(2500))
        for line in lines.dropLast() where !line.isEmpty {
            append(id, readableLine(line))
        }
    }

    private func launch(_ id: JarvisAgentID, executable: String, arguments: [String], isProbe: Bool,
                        workingDirectory: URL? = nil, pilotID: UUID? = nil, sanityRunID: UUID? = nil) {
        // 같은 CLI는 하나만. 밤 지식 작업·Sanity 등록은 부르는 쪽에서 isAnyRunning을 먼저 확인한다.
        guard processes[id] == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory ?? workspace
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        let paths = [URL(fileURLWithPath: executable).deletingLastPathComponent().path,
                     "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = (paths + [environment["PATH"] ?? ""]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        if pilotID != nil {
            // Publishing/third-party API credentials are unnecessary for a
            // local pilot. Do not add them to the subprocess environment.
            for key in Array(environment.keys) where
                ["SANITY", "VERCEL", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ELEVENLABS_API_KEY", "GEMINI_API_KEY"].contains(where: { key.uppercased().contains($0) }) {
                environment.removeValue(forKey: key)
            }
        }
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        partialLines[id] = ""
        runKinds[id] = isProbe
        update(id) {
            $0.state = isProbe ? .checking : .running
            $0.logs = []
            $0.lastRun = UUID()
            $0.lastExitCode = nil
            $0.updatedAt = Date()
        }
        let topicCode = knowledgePilot.map { String($0.directory.lastPathComponent.prefix(6)) } ?? "Knowledge"
        append(id, isProbe ? "CLI --version 실행" : pilotID != nil ? topicCode + " · 로컬 산출물 제작" : sanityRunID != nil ? "Sanity 검토용 초안 등록 · 공개 금지" : "CLI 실행")
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.receive(id, data: data) }
        }
        process.terminationHandler = { [weak self] ended in
            output.fileHandleForReading.readabilityHandler = nil
            let tail = output.fileHandleForReading.readDataToEndOfFile()
            let code = ended.terminationStatus
            let signal = ended.terminationReason == .uncaughtSignal
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.receive(id, data: tail)
                if let last = self.partialLines[id], !last.isEmpty {
                    self.append(id, self.readableLine(last))
                }
                self.partialLines[id] = nil
                self.processes[id] = nil
                let probe = self.runKinds.removeValue(forKey: id) ?? false
                let aborted = signal
                self.update(id) {
                    $0.lastExitCode = code
                    $0.state = aborted ? .cancelled :
                        code == 0 ? (probe ? .ready : .completed) : .failed
                    if probe, code == 0 {
                        $0.version = $0.logs.last(where: {
                            !$0.contains("CLI --version") && !$0.isEmpty
                        }) ?? ""
                    }
                    if probe { $0.logs = [] } // Probe output is not an AI task.
                    $0.updatedAt = Date()
                }
                if !probe {
                    self.append(id, "프로세스 종료 · 코드 " + String(code) +
                                (aborted ? " · 사용자 중단" : code == 0 ? " · 정상 완료" : " · 오류"))
                    self.record(id.title + " · 종료 코드 " + String(code) +
                                (aborted ? " · 중단" : ""))
                }
                // P2 C2: 출력에서 사용 한도 메시지를 찾는다 (구독 한도 · 429 · resets at …)
                var limitNote: String?
                if !probe, let hit = Self.limitMessage(in: self.lane(id).logs.suffix(60)) {
                    self.limitHits[id] = (Date(), hit)
                    limitNote = hit
                    self.append(id, "⚠️ 사용 한도 도달" + (hit.isEmpty ? "" : " · " + hit))
                    self.record(id.title + " · 사용 한도 도달")
                } else if !probe, code == 0 {
                    self.limitHits[id] = nil
                }
                // P1 완료 알림: 직접 맡긴 작업과 수동 지식 작업만. 밤 근무·Sanity 등록은 조용히 둔다.
                if !probe && sanityRunID == nil && !(pilotID != nil && self.nightShiftRunning) {
                    var detail = self.lane(id).logs.suffix(40).joined(separator: "\n")
                    if let limitNote {
                        detail = "사용 한도에 걸려 작업을 끝내지 못함. " + limitNote + "\n" + detail
                    }
                    if pilotID != nil, let folder = self.knowledgePilot?.directory,
                       let result = try? String(contentsOf: folder.appendingPathComponent("result.md"), encoding: .utf8) {
                        detail = result
                    }
                    JarvisCompletionNotices.shared.report(agent: id.title, ok: code == 0,
                                                          cancelled: aborted, detail: detail)
                }
                if let pilotID {
                    self.finishKnowledgePilot(id: pilotID, code: code, aborted: aborted)
                }
                if let sanityRunID {
                    self.finishSanityStage(id: sanityRunID, code: code, aborted: aborted)
                }
            }
        }
        do {
            try process.run()
            processes[id] = process
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            processes[id] = nil
            runKinds[id] = nil
            update(id) { $0.state = .failed }
            append(id, "실행 실패: " + error.localizedDescription)
            if let pilotID {
                knowledgePilotError = error.localizedDescription
                finishKnowledgePilot(id: pilotID, code: 1, aborted: false)
            }
            if let sanityRunID {
                finishSanityStage(id: sanityRunID, code: 1, aborted: false)
            }
        }
    }
}
