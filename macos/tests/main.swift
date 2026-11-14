import Foundation

let screen = """
AWS console
Build failed
HTTP 403 Forbidden
권한 없음: access denied
Login
Settings
"""

let errorAnswer = LocalScreenInsights.answer(question: "이 화면에서 오류가 뭐야?", recognizedText: screen)
precondition(errorAnswer.contains("Build failed"))
precondition(errorAnswer.contains("HTTP 403 Forbidden"))
precondition(errorAnswer.contains("원인이나 해결 완료 여부"))
print("PASS error candidates")

let searchAnswer = LocalScreenInsights.answer(question: "Login 찾아줘", recognizedText: screen)
precondition(searchAnswer.contains("- Login"))
precondition(searchAnswer.contains("실제 버튼 위치"))
print("PASS keyword lookup")

let summaryAnswer = LocalScreenInsights.answer(question: "화면 요약해줘", recognizedText: "파일 관리\n프로젝트 현황\n진행 중")
precondition(summaryAnswer.contains("글자 3줄"))
precondition(summaryAnswer.contains("프로젝트 현황"))
print("PASS bounded text summary")

let secretAnswer = LocalScreenInsights.answer(question: "이 화면에서 오류가 뭐야?", recognizedText: "API_KEY=private-token\nERROR: bad secret")
precondition(!secretAnswer.contains("private-token"))
precondition(secretAnswer.contains("해당 줄을 숨겼습니다"))
print("PASS credential masking")

let missingAnswer = LocalScreenInsights.answer(question: "화면에 오류 있어?", recognizedText: "")
precondition(missingAnswer.contains("아직 인식한 화면 글자"))
print("PASS no capture fallback")

let controls = [
    ScreenUIEvidence(role: "AXButton", label: "저장"),
    ScreenUIEvidence(role: "AXTab", label: "설정"),
    ScreenUIEvidence(role: "AXTextField", label: "[입력 요소: 내용 비공개]"),
    ScreenUIEvidence(role: "AXButton", label: "API_KEY=hidden-credential")
]
let uiAnswer = LocalScreenInsights.answer(question: "선택한 앱에 버튼이 뭐가 있어?", recognizedText: "", uiElements: controls)
precondition(uiAnswer.contains("버튼: 저장"))
precondition(uiAnswer.contains("탭: 설정"))
precondition(uiAnswer.contains("입력 요소 1개"))
precondition(!uiAnswer.contains("hidden-credential"))
precondition(uiAnswer.contains("해당 줄을 숨겼습니다"))
precondition(uiAnswer.contains("어떤 버튼도 누르지"))
print("PASS selected app accessibility controls, redaction, no click")

let noInspection = LocalScreenInsights.answer(question: "버튼 있어?", recognizedText: "화면 글자", uiElements: [])
precondition(noInspection.contains("UI 구조 확인 기록이 없어요"))
print("PASS no implicit accessibility inspection")

let allowed = [
    ("AXButton", "Refresh"), ("AXButton", "새로고침"),
    ("AXButton", "Reload this page"), ("AXButton", "  reload ")
]
for (role, label) in allowed {
    precondition(JarvisSafePressPolicy.allows(role: role, label: label))
}
let blocked = [
    ("AXButton", "Delete"), ("AXButton", "삭제"),
    ("AXButton", "Send"), ("AXButton", "Submit"),
    ("AXButton", "결제"), ("AXButton", "게시"),
    ("AXButton", "Save"), ("AXButton", "새로고침 삭제"),
    ("AXButton", "Refresh now and delete"),
    ("AXTab", "Refresh"), ("AXTextField", "새로고침"),
    ("AXMenuItem", "Refresh"), ("AXButton", "")
]
for (role, label) in blocked {
    precondition(!JarvisSafePressPolicy.allows(role: role, label: label),
                 "Unexpected allowed action: \(role) \(label)")
}
print("PASS exact-label refresh-only policy blocks destructive/ambiguous controls")

let projectFixture = """
{"items":[{"id":2,"name":"DECHIVE.WIKI","goal":"배포",
"repo_full_name":"Aprasaks/dechive-wiki",
"tasks":[{"id":11,"title":"AWS 확인","status":"todo"}],
"task_counts":{"todo":1,"doing":0,"blocked":0,"done":0},
"last_check":{"branch":"main","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
"workflow_state":"unavailable","workflow_conclusion":"unknown",
"checked_at":"2026-11-14T00:00:00+00:00"}},
{"id":3,"name":"Local notes","goal":"개인 메모","repo_full_name":"",
"tasks":[],"task_counts":{"todo":0,"doing":0,"blocked":0,"done":0},"last_check":null}]}
"""
let workDecoder = JSONDecoder()
workDecoder.keyDecodingStrategy = .convertFromSnakeCase
let workDecoded = try workDecoder.decode(WorkProjectsReply.self, from: Data(projectFixture.utf8))
precondition(workDecoded.items.count == 2)
precondition(workDecoded.items[0].lastCheck?.headSha.hasPrefix("aaaaaaaa") == true)
precondition(workDecoded.items[0].taskCounts.todo == 1)
let safeProposal = WorkCheckProposal.forProject(workDecoded.items[0])
precondition(safeProposal?.repository == "Aprasaks/dechive-wiki")
precondition(safeProposal?.explanation.contains("파일 변경·푸시·배포·삭제는 하지 않습니다") == true)
precondition(WorkCheckProposal.forProject(workDecoded.items[1]) == nil)
print("PASS local project decoding and read-only proposal contract")

let states = WorkTaskState.allCases.map { $0.rawValue }
precondition(states == ["todo", "doing", "blocked", "done"])
precondition(WorkTaskState.doing.label == "진행")
let continuityFixture = """
{"items":[{"id":7,"name":"TEST","goal":"","repo_full_name":"",
"tasks":[
{"id":1,"title":"할 일 A","status":"todo"},
{"id":2,"title":"막힌 작업","status":"blocked"},
{"id":3,"title":"진행 중인 B","status":"doing"},
{"id":4,"title":"완료 작업","status":"done"},
{"id":5,"title":"할 일 C","status":"todo"}
],"task_counts":{"todo":2,"doing":1,"blocked":1,"done":1},
"last_check":null}]}
"""
let continuity = try workDecoder.decode(WorkProjectsReply.self, from: Data(continuityFixture.utf8)).items[0]
precondition(continuity.nextTasks.map { $0.title } == ["진행 중인 B", "할 일 A", "할 일 C"])
precondition(continuity.blockedTasks.map { $0.title } == ["막힌 작업"])
precondition(continuity.nextTasks.allSatisfy { $0.status != "done" })
print("PASS persisted tasks provide deterministic doing-first next steps")

let handoffTime = Date(timeIntervalSince1970: 1_700_000_000)
let unlinked = JarvisHandoffReport.make(
    project: workDecoded.items[1], localFolderConnected: false,
    localEvidence: nil, createdAt: handoffTime)
precondition(unlinked.body.contains("등록된 진행/예정 작업 없음"))
precondition(unlinked.body.contains("연결된 Mac 폴더 없음"))
precondition(unlinked.body.contains("확인 기록 없음"))
precondition(unlinked.body.contains("AWS 배포·사이트 공개"))
precondition(unlinked.body.contains("요약 생성: "))
print("PASS handoff reports missing evidence without inventing completion")

let localSample = LocalGitEvidence(
    rootPath: "/private/not-for-clipboard/local-project",
    branch: "feature/local", headSHA: String(repeating: "b", count: 40),
    changedTrackedEntries: 2, untrackedEntries: 1, checkedAt: handoffTime)
let linkedReport = JarvisHandoffReport.make(
    project: workDecoded.items[0], localFolderConnected: true,
    localEvidence: localSample, createdAt: handoffTime)
precondition(linkedReport.body.contains("Mac 로컬 Git"))
precondition(linkedReport.body.contains("feature/local"))
precondition(linkedReport.body.contains("추적 2, 미추적 1"))
precondition(linkedReport.body.contains("HEAD: " + String(repeating: "b", count: 40)))
precondition(linkedReport.body.contains("GitHub · 마지막 승인 조회 기록"))
precondition(linkedReport.body.contains(String(repeating: "a", count: 40)))
precondition(linkedReport.body.contains("Workflow: 당시 HEAD와 일치하는 실행 증거를 확인하지 못함"))
precondition(!linkedReport.body.contains("/private/not-for-clipboard"))
precondition(linkedReport.body.contains("현재 시점 재검사 아님"))
print("PASS handoff separates last local Git and last GitHub evidence without path exposure")

let taskReport = JarvisHandoffReport.make(
    project: continuity, localFolderConnected: true,
    localEvidence: nil, createdAt: handoffTime)
precondition(taskReport.body.contains("[진행] 진행 중인 B"))
precondition(taskReport.body.contains("[예정] 할 일 A"))
precondition(taskReport.body.contains("[막힘] 막힌 작업"))
precondition(!taskReport.body.contains("[진행] 완료 작업"))
precondition(taskReport.body.contains("폴더는 연결됐지만 이번 실행에서 Git 상태 확인 기록이 없음"))
print("PASS handoff preserves next tasks, blockers, and unverified local state")


// v2.6 — a proposed app-open action is inert until a direct approval.
// All test openers are mocks; no Finder or browser is launched.
let openProject = workDecoded.items[0]
let expectedGitHub = "https://github.com/Aprasaks/dechive-wiki"
precondition(JarvisWorkspaceResume.githubURL(for: openProject.repoFullName)?.absoluteString == expectedGitHub)
for invalid in ["", "owner", "owner/repo/path", "owner/repo?x=1",
                "owner/../repo", "owner/%2e%2e", "https://evil.test/repo",
                "owner/repo#frag", "owner/repo with spaces"] {
    precondition(JarvisWorkspaceResume.githubURL(for: invalid) == nil,
                 "Invalid GitHub destination accepted: \(invalid)")
}
precondition(JarvisWorkspaceResume.prepare(
    project: openProject, linkedFolder: nil,
    openFolder: false, openGitHub: false) == nil)
precondition(JarvisWorkspaceResume.prepare(
    project: openProject, linkedFolder: nil,
    openFolder: true, openGitHub: false) == nil)

let referenceTime = Date(timeIntervalSince1970: 1_700_000_000)
guard let browserProposal = JarvisWorkspaceResume.prepare(
    project: openProject, linkedFolder: nil,
    openFolder: false, openGitHub: true, now: referenceTime) else {
    preconditionFailure("Safe GitHub proposal not created")
}
var openedURLs: [URL] = []
let approvedBrowser = JarvisWorkspaceResume.perform(
    proposal: browserProposal, currentProject: openProject,
    currentLinkedFolder: nil, now: referenceTime.addingTimeInterval(8),
    opener: { url in openedURLs.append(url); return true })
precondition(openedURLs.map { $0.absoluteString } == [expectedGitHub])
precondition(approvedBrowser.summary.contains("열기 요청 수락"))
precondition(approvedBrowser.summary.contains("실제 페이지 로딩"))
precondition(!approvedBrowser.summary.contains("배포 완료"))
print("PASS one-shot user-scoped GitHub open request and accurate result")

openedURLs = []
let expired = JarvisWorkspaceResume.perform(
    proposal: browserProposal, currentProject: openProject,
    currentLinkedFolder: nil, now: referenceTime.addingTimeInterval(150),
    opener: { url in openedURLs.append(url); return true })
precondition(openedURLs.isEmpty && expired.summary.contains("실행 차단"))
let mismatched = JarvisWorkspaceResume.perform(
    proposal: browserProposal, currentProject: workDecoded.items[1],
    currentLinkedFolder: nil, now: referenceTime,
    opener: { url in openedURLs.append(url); return true })
precondition(openedURLs.isEmpty && mismatched.summary.contains("실행 차단"))
let unavailable = JarvisWorkspaceResume.perform(
    proposal: browserProposal, currentProject: openProject,
    currentLinkedFolder: nil, now: referenceTime,
    opener: { url in openedURLs.append(url); return false })
precondition(openedURLs.count == 1 && unavailable.summary.contains("요청 실패"))
print("PASS expired/retargeted approvals blocked and failures not shown as success")

let temp = FileManager.default.temporaryDirectory
    .appendingPathComponent("jarvis-v26-test-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temp.appendingPathComponent(".git"),
                                        withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
let path = temp.standardizedFileURL.resolvingSymlinksInPath().path
guard let folderProposal = JarvisWorkspaceResume.prepare(
    project: openProject, linkedFolder: path,
    openFolder: true, openGitHub: false, now: referenceTime) else {
    preconditionFailure("Linked Git folder proposal not created")
}
openedURLs = []
let validFolder = JarvisWorkspaceResume.perform(
    proposal: folderProposal, currentProject: openProject,
    currentLinkedFolder: path, now: referenceTime,
    opener: { url in openedURLs.append(url); return true })
precondition(openedURLs.count == 1 && openedURLs[0].isFileURL)
precondition(validFolder.summary.contains("Finder: 선택한 로컬 프로젝트 폴더 열기 요청 수락"))
openedURLs = []
let changedFolder = JarvisWorkspaceResume.perform(
    proposal: folderProposal, currentProject: openProject,
    currentLinkedFolder: "/unexpected/new-folder", now: referenceTime,
    opener: { url in openedURLs.append(url); return true })
precondition(openedURLs.isEmpty && changedFolder.summary.contains("실행 차단"))
try FileManager.default.removeItem(at: temp.appendingPathComponent(".git"))
let removedGit = JarvisWorkspaceResume.perform(
    proposal: folderProposal, currentProject: openProject,
    currentLinkedFolder: path, now: referenceTime,
    opener: { url in openedURLs.append(url); return true })
precondition(openedURLs.isEmpty && removedGit.summary.contains("Git 루트가 아닙니다"))
print("PASS connected folder scope and missing Git root checks without opening Finder")

// v2.7 — Korean voice / text project routing never opens apps on its own.
let routedFixtures = workDecoded.items
precondition(!JarvisWorkspaceCommandParser.isOpenRequest("DECHIVE.WIKI 현재 상태 알려줘"))
precondition(JarvisWorkspaceCommandParser.isOpenRequest("DECHIVE.WIKI 작업 이어서 열어줘"))
switch JarvisWorkspaceCommandParser.parse("DECHIVE.WIKI 작업 이어서 열어줘", projects: routedFixtures) {
case .matched(let request):
    precondition(request.projectId == 2)
    precondition(request.projectName == "DECHIVE.WIKI")
    precondition(request.repository == "Aprasaks/dechive-wiki")
    precondition(request.destination == .choose)
    let proposal = JarvisWorkspaceResume.prepare(project: routedFixtures[0],
        linkedFolder: nil, openFolder: false, openGitHub: true)
    precondition(proposal?.githubURL?.absoluteString == "https://github.com/Aprasaks/dechive-wiki")
    print("PASS voice request resolves registered project to proposal, no action")
default:
    preconditionFailure("Expected exact named project request")
}
switch JarvisWorkspaceCommandParser.parse(
    "dechive.wiki 깃허브 열어줘", projects: routedFixtures) {
case .matched(let request): precondition(request.destination == .github)
default: preconditionFailure("Explicit GitHub destination not recognized")
}
switch JarvisWorkspaceCommandParser.parse(
    "DECHIVE.WIKI 폴더 열어줘", projects: routedFixtures) {
case .matched(let request): precondition(request.destination == .folder)
default: preconditionFailure("Explicit Finder destination not recognized")
}
switch JarvisWorkspaceCommandParser.parse("내 프로젝트 열어줘", projects: routedFixtures) {
case .missingProject: break
default: preconditionFailure("Ambiguous project was guessed")
}
switch JarvisWorkspaceCommandParser.parse(
    "DECHIVE.WIKI 작업 열고 배포해줘", projects: routedFixtures) {
case .unsupported: break
default: preconditionFailure("Unsafe command was misrouted")
}
switch JarvisWorkspaceCommandParser.parse(
    "DECHIVE.WIKI 작업 열어줘",
    projects: routedFixtures + [
        WorkProject(id: 99, name: "DECHIVE", goal: "", repoFullName: "",
                    tasks: [], taskCounts: WorkCounts(todo: 0, doing: 0, blocked: 0, done: 0),
                    lastCheck: nil)
    ]) {
case .ambiguous: break
default: preconditionFailure("Overlapping names must not be guessed")
}
switch JarvisWorkspaceCommandParser.parse("오늘 날씨 알려줘", projects: routedFixtures) {
case .ordinary: break
default: preconditionFailure("Ordinary chat must remain ordinary")
}
print("PASS exact project resolution, explicit destination, ambiguous/unsafe/unknown handling")
