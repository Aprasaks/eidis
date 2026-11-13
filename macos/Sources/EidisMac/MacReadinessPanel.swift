import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices
import Speech
import SwiftUI

// Every diagnostic has an explicit evidence boundary. A permission granted
// is not proof that audio transcription or screen capture actually succeeded.
struct DiagnosticFinding: Identifiable {
    let id: String
    let title: String
    let kind: String          // verified / attention / manual
    let detail: String
}

@MainActor
final class MacReadinessDiagnostics: ObservableObject {
    @Published private(set) var findings: [DiagnosticFinding] = []
    @Published private(set) var checkedAt: Date?
    @Published private(set) var busy = false

    func run() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        var rows: [DiagnosticFinding] = []

        func append(_ id: String, _ title: String, _ kind: String, _ detail: String) {
            rows.append(DiagnosticFinding(id: id, title: title, kind: kind, detail: detail))
        }

        let microphoneUsage = Bundle.main.object(
            forInfoDictionaryKey: "NSMicrophoneUsageDescription"
        ) != nil
        let speechUsage = Bundle.main.object(
            forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription"
        ) != nil
        append("bundle", "앱 개인정보 권한 설명",
               microphoneUsage && speechUsage ? "verified" : "attention",
               microphoneUsage && speechUsage
               ? "이 앱에 마이크와 음성 인식 권한 설명이 포함되어 있습니다."
               : "패키징된 JARVIS.app으로 실행해야 권한 요청이 안전합니다.")

        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        append("microphone", "Mac 마이크 권한",
               mic == .authorized ? "verified" : "attention",
               mic == .authorized ? "권한 허용됨 · 실제 소리 입력은 아직 확인하지 않았습니다."
               : mic == .notDetermined ? "미결정 · 음성 탭에서 직접 시작하면 권한을 요청합니다."
               : "허용되지 않음 · 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 확인하세요.")

        let speech = SFSpeechRecognizer.authorizationStatus()
        append("speech_permission", "Mac 음성 인식 권한",
               speech == .authorized ? "verified" : "attention",
               speech == .authorized ? "권한 허용됨 · 실제 한국어 인식 성공 여부와는 별개입니다."
               : speech == .notDetermined ? "미결정 · 음성 탭에서 수동 승인 필요"
               : "허용되지 않음 · 시스템 설정 > 개인정보 보호 및 보안 > 음성 인식 확인")

        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")) {
            let supported = recognizer.supportsOnDeviceRecognition
            append("speech_device", "한국어 온디바이스 인식 지원",
                   supported && recognizer.isAvailable ? "verified" : "attention",
                   !supported ? "이 Mac에서 한국어 온디바이스 인식이 지원되지 않습니다. 외부 서버 인식은 자동으로 사용하지 않습니다."
                   : recognizer.isAvailable ? "인식 기능 이용 가능 · 실제로 말을 인식했는지는 별도 확인 필요"
                   : "한국어 음성 인식 서비스가 현재 사용 불가능합니다.")
        } else {
            append("speech_device", "한국어 온디바이스 인식 지원", "attention",
                   "한국어 음성 인식기를 만들 수 없습니다.")
        }

        let screen = CGPreflightScreenCaptureAccess()
        append("screen", "Mac 화면 기록 권한",
               screen ? "verified" : "attention",
               screen ? "권한 허용 상태 · 실제 화면 한 장 캡처는 아직 하지 않았습니다."
               : "권한 미확인/미허용 · 화면 탭에서 수동 캡처를 시도하고 설정에서 확인하세요.")

        let accessibility = AXIsProcessTrusted()
        append("accessibility", "손쉬운 사용 권한",
               accessibility ? "verified" : "attention",
               accessibility ? "권한 허용됨 · 다른 앱 조작 기능이 작동한다는 뜻은 아닙니다."
               : "권한 미허용 · UI 구조 읽기 기능은 별도 승인 필요")

        // No network requests other than loopback. This only reads local facts.
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8765/api/diagnostics")!)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["scope"] as? String == "local_read_only" else {
                append("server", "로컬 자비스 서버", "attention",
                       "진단 응답이 예상한 형식이 아닙니다. 앱과 서버 버전이 같은지 확인하세요.")
                findings = rows
                checkedAt = Date()
                return
            }
            append("server", "로컬 자비스 서버", "verified",
                   "127.0.0.1:8765에서 최신 읽기 전용 진단 응답을 받았습니다.")
            let database = result["database"] as? [String: Any] ?? [:]
            let databaseOK = (database["status"] as? String == "ok")
            append("database", "SQLite 데이터베이스 읽기 점검",
                   databaseOK ? "verified" : "attention",
                   databaseOK ? "SQLite quick_check 정상 · 저장/쓰기 테스트는 하지 않았습니다."
                   : "SQLite 읽기 점검 실패 · 로컬 데이터 손상 여부를 확인하세요.")
            let projects = result["projects"] as? [String: Any] ?? [:]
            let count = projects["exact_count"] as? Int
            append("projects", "프로젝트 기록 조회",
                   count != nil ? "verified" : "attention",
                   count.map { "로컬 프로젝트 \($0)개 조회 · 작업 내용은 외부로 전송하지 않았습니다." }
                   ?? "프로젝트 개수를 확인하지 못했습니다.")
            let tools = result["tools"] as? [String: Any] ?? [:]
            let manifest = tools["manifest"] as? [String: Any] ?? [:]
            let allTools = manifest["tools"] as? [[String: Any]] ?? []
            let readOnly = (manifest["write_tools_enabled"] as? Bool == false)
                && allTools.contains { $0["name"] as? String == "github.public_verify" }
            append("tool", "GitHub 확인 도구 등록",
                   readOnly ? "verified" : "attention",
                   readOnly ? "공개 저장소 읽기 전용 도구가 등록돼 있습니다. GitHub 실제 응답은 별도 시험 필요."
                   : "허용 도구 목록을 정상적으로 확인하지 못했습니다.")
            let history = tools["latest_run"] as? [[String: Any]] ?? []
            if let last = history.first,
               let status = last["status"] as? String,
               let outcome = last["outcome"] as? String {
                append("last_run", "마지막 도구 실행 영수증", "manual",
                       "로컬 기록: \(status) / \(outcome). 현재 GitHub 상태를 다시 확인한 것은 아닙니다.")
            } else {
                append("last_run", "마지막 도구 실행 영수증", "manual",
                       "아직 기록된 도구 실행이 없습니다.")
            }
        } catch {
            append("server", "로컬 자비스 서버", "attention",
                   "로컬 서버에 연결할 수 없습니다. START_JARVIS_MAC.command로 실행했는지 확인하세요.")
            append("database", "SQLite 데이터베이스", "manual",
                   "서버가 연결되지 않아 로컬 DB를 확인할 수 없었습니다.")
            append("tool", "GitHub 확인 도구", "manual",
                   "서버가 연결되지 않아 도구 등록 여부를 확인할 수 없었습니다.")
        }

        append("voice_live", "실제 한국어 음성 → 자비스 응답", "manual",
               "아직 미검증 · 음성 탭에서 말하기 → 완료하고 명령 전달 → 한국어 응답 듣기를 직접 시험하세요.")
        append("github_live", "실제 GitHub 공개 API 조회", "manual",
               "아직 미검증 · 프로젝트에 공개 owner/repo를 등록하고 상태 확인을 직접 요청하세요. 자동 실행 없음.")
        append("screen_live", "실제 화면 한 장 캡처", "manual",
               "아직 미검증 · 화면 탭에서 직접 '화면 1장 확인'을 누르세요. 자동 업로드 없음.")

        findings = rows
        checkedAt = Date()
    }

    var report: String {
        let moment = checkedAt?.formatted(date: .abbreviated, time: .standard)
            ?? "미실행"
        let details = findings.map { item in
            "\(item.title) [\(item.kind)]: \(item.detail)"
        }.joined(separator: "\n")
        return "JARVIS Mac 로컬 진단 · \(moment)\n"
            + "실제 실기기 확인에만 유효하며, 미검증 항목은 성공으로 표시하지 않습니다.\n"
            + details
    }
}

struct MacReadinessPanel: View {
    @StateObject private var diagnostics = MacReadinessDiagnostics()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac 실기기 점검")
                        .font(.title3.weight(.medium))
                    Text("명령을 실행하지 않고 현재 권한·로컬 서버·저장소·도구 상태만 확인합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("진단 실행") {
                    Task { await diagnostics.run() }
                }
                .disabled(diagnostics.busy)
                Button("결과 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics.report, forType: .string)
                }
                .disabled(diagnostics.findings.isEmpty || diagnostics.busy)
            }
            if diagnostics.busy {
                ProgressView("확인 중…")
                    .progressViewStyle(.linear)
            }
            if diagnostics.findings.isEmpty && !diagnostics.busy {
                ContentUnavailableView("아직 실행한 진단이 없습니다.",
                                       systemImage: "stethoscope",
                                       description: Text("진단 실행을 눌러 Mac에서 현재 확인 가능한 항목을 검사하세요."))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(diagnostics.findings) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.kind == "verified" ? "checkmark.circle"
                                  : item.kind == "manual" ? "questionmark.circle"
                                  : "exclamationmark.triangle")
                                .foregroundStyle(item.kind == "verified" ? .green
                                                 : item.kind == "manual" ? .secondary
                                                 : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.medium))
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            Text("권한 상태 확인은 마이크·화면을 켜지 않습니다. '권한 허용'은 실제 음성 인식 성공이 아닙니다. GitHub 조회도 여기서는 실행하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
    }
}
