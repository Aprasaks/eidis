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
