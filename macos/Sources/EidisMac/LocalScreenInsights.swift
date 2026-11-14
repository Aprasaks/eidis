import Foundation

/// Answers simple questions from OCR text on-device, without an LLM.
/// It cannot see pixels, determine screen coordinates, or diagnose root causes.
struct ScreenUIEvidence {
    let role: String
    let label: String
}

enum LocalScreenInsights {
    static func answer(question: String, recognizedText: String,
                       uiElements: [ScreenUIEvidence] = []) -> String {
        let lines = recognizedText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "화면에 대해 궁금한 점을 입력해 주세요." }

        let lower = query.lowercased()
        // An accessibility reading applies ONLY to the explicitly selected app.
        // It is not necessarily the same app as the desktop-wide OCR image.
        if let uiReply = uiAnswer(question: lower, elements: uiElements) {
            return uiReply
        }
        guard !lines.isEmpty else {
            return "아직 인식한 화면 글자가 없습니다. 화면 캡처 + 글자 읽기를 먼저 실행해 주세요. 앱 버튼·탭은 UI 구조 확인을 별도로 눌러 읽을 수 있어요."
        }
        if matches(lower, any: ["오류", "에러", "실패", "경고", "문제", "안돼", "안 되", "error", "fail", "warning", "exception"]) {
            let errors = lines.filter { line in
                let value = line.lowercased()
                return matches(value, any: [
                    "error", "failed", "failure", "exception", "traceback", "forbidden",
                    "permission denied", "unauthorized", "timed out", "timeout",
                    "http 400", "http 401", "http 403", "http 404", "http 429",
                    "http 500", "http 502", "http 503",
                    "오류", "에러", "실패", "경고", "거부", "권한 없음",
                    "접근할 수 없", "시간 초과", "연결할 수 없"
                ])
            }
            if errors.isEmpty {
                return "인식된 글자 \(lines.count)줄에서 오류를 직접 나타내는 문구를 찾지 못했어요. 화면에 문제가 없다는 뜻은 아닙니다. OCR이 놓친 글자나 이미지 상태는 알 수 없어요."
            }
            return "인식된 화면 글자에서 오류·실패 관련 문구 \(errors.count)줄을 찾았어요:\n"
                + excerpt(errors)
                + "\n위 문구는 문제의 단서일 뿐, 실제 원인이나 해결 완료 여부는 확인하지 않았어요."
        }

        let keywords = query
            .split(whereSeparator: { $0.isWhitespace || ",.?!:;()[]".contains($0) })
            .map { String($0).lowercased() }
            .filter { $0.count >= 2 && ![
                "지금", "여기", "화면", "내용", "어디", "어떤", "있어", "있니",
                "보여", "알려줘", "설명해줘", "찾아줘", "찾아", "해줘", "뭐야", "무엇",
                "요약", "정리", "어떻게", "the", "and", "please", "show", "find",
            ].contains($0) }
        if matches(lower, any: ["찾아", "어디", "보여", "있는지"]) && !keywords.isEmpty {
            let found = lines.filter { line in keywords.contains { line.lowercased().contains($0) } }
            if !found.isEmpty {
                return "질문에 포함된 단어와 일치하는 화면 글자를 찾았어요:\n"
                    + excerpt(found)
                    + "\n실제 버튼 위치나 클릭 가능한 상태까지 확인한 것은 아니에요."
            }
        }

        return "이번에 캡처한 화면에서 글자 \(lines.count)줄을 인식했어요. 앞쪽 내용은 다음과 같아요:\n"
            + excerpt(lines)
            + "\n이 답변은 OCR 텍스트만 정리한 것이에요. 화면의 그림이나 동작, 오류의 원인은 판단하지 않았어요."
    }

    private static func uiAnswer(question: String, elements: [ScreenUIEvidence]) -> String? {
        guard matches(question, any: [
            "버튼", "메뉴", "탭", "체크박스", "입력창", "입력 필드",
            "클릭", "누를", "누르면", "ui 구조", "컨트롤", "button", "menu", "tab"
        ]) else { return nil }
        guard !elements.isEmpty else {
            return "선택한 앱의 UI 구조 확인 기록이 없어요. 앱을 직접 선택하고 '선택 앱 UI 구조 읽기'를 눌러 주세요. 자동으로 다른 앱을 살피지 않습니다."
        }
        let controlRoles: [String: String] = [
            "AXButton": "버튼", "AXMenuItem": "메뉴",
            "AXMenuBarItem": "메뉴", "AXCheckBox": "체크박스",
            "AXRadioButton": "라디오", "AXTab": "탭",
            "AXPopUpButton": "선택 메뉴"
        ]
        let visibleControls = elements.filter { controlRoles[$0.role] != nil }
        let inputs = elements.filter {
            ["AXTextField", "AXTextArea", "AXSecureTextField",
             "AXComboBox", "AXSearchField", "AXTextView"].contains($0.role)
        }
        if visibleControls.isEmpty && inputs.isEmpty {
            return "선택 앱에서 UI 요소 \(elements.count)개를 읽었지만 버튼·메뉴·입력 필드 정보는 확인하지 못했어요. 접근성 정보가 제한될 수 있습니다."
        }
        let controls = visibleControls.prefix(10).map { item in
            let type = controlRoles[item.role] ?? "컨트롤"
            let label = item.label.isEmpty ? "(제목 없음)" : safeLine(item.label)
            return "- \(type): \(label)"
        }
        let rest = visibleControls.count > 10 ? "\n- 외 \(visibleControls.count - 10)개" : ""
        let inputSummary = inputs.isEmpty ? "" : "\n- 입력 요소 \(inputs.count)개 (내용 읽지 않음)"
        return "직접 선택한 앱의 접근성 UI 기록입니다. 이름이 있는 컨트롤 후보 \(visibleControls.count)개:\n"
            + controls.joined(separator: "\n") + rest + inputSummary
            + "\n이것은 UI 역할·제목 목록일 뿐 실제 위치, 클릭 가능 여부, 현재 OCR 화면과 동일한 창인지는 확인하지 않았어요. 어떤 버튼도 누르지 않았습니다."
    }

    private static func matches(_ value: String, any terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }

    private static func excerpt(_ lines: [String]) -> String {
        let shown = lines.prefix(5).map { "- " + safeLine($0) }.joined(separator: "\n")
        return lines.count > 5 ? shown + "\n- … 외 \(lines.count - 5)줄" : shown
    }

    private static func safeLine(_ value: String) -> String {
        let lower = value.lowercased()
        if matches(lower, any: [
            "password", "passwd", "api_key", "api key", "secret",
            "bearer ", "access_token", "access key", "비밀번호", "인증번호", "복구 코드"
        ]) {
            return "[민감한 인증 정보가 포함될 수 있어 해당 줄을 숨겼습니다]"
        }
        return String(value.prefix(160))
    }
}
