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
