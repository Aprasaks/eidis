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
