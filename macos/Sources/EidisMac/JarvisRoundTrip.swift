import Foundation

/// A one-shot LOCAL native-to-server command check. It does not use the
/// microphone, change saved tasks, open apps or consent to remote AI calls.
/// A response is verified only if the exact JARVIS eidis project exists and
/// the loopback brain returns its expected read-only action.
struct JarvisRoundTripFinding {
    let passed: Bool
    let detail: String
    let testedAt: Date
}

enum JarvisRoundTrip {
    struct ProjectsEnvelope: Decodable {
        let items: [Project]
    }
    struct Project: Decodable {
        let name: String
        let repoFullName: String
        enum CodingKeys: String, CodingKey {
            case name
            case repoFullName = "repo_full_name"
        }
    }
    struct ChatReply: Decodable {
        let action: String
        let executed: Bool
        let brainSource: String?
        let text: String
        enum CodingKeys: String, CodingKey {
            case action, executed, text
            case brainSource = "brain_source"
        }
    }

    static func isConfirmed(_ reply: ChatReply, selfProjectFound: Bool) -> Bool {
        selfProjectFound &&
        reply.action == "project_self_overview" &&
        !reply.executed &&
        reply.brainSource == "local" &&
        reply.text.contains("자비스 자신의 프로젝트 기록")
    }

    static func check(
        session: URLSession = .shared,
        timestamp: Date = Date()
    ) async -> JarvisRoundTripFinding {
        let base = "http://127.0.0.1:8765"
        do {
            var listing = URLRequest(url: URL(string: base + "/api/projects")!)
            listing.timeoutInterval = 5
            listing.cachePolicy = .reloadIgnoringLocalCacheData
            let (listData, listingResponse) = try await session.data(for: listing)
            guard (listingResponse as? HTTPURLResponse)?.statusCode == 200 else {
                return JarvisRoundTripFinding(
                    passed: false, detail: "로컬 프로젝트 조회에 실패했습니다. 작업 상태는 변경하지 않았습니다.",
                    testedAt: timestamp)
            }
            let projects = try JSONDecoder().decode(ProjectsEnvelope.self, from: listData)
            let exact = projects.items.filter {
                $0.name == "JARVIS eidis" &&
                $0.repoFullName == "Aprasaks/eidis"
            }
            guard exact.count == 1 else {
                return JarvisRoundTripFinding(
                    passed: false,
                    detail: "JARVIS eidis 정확한 등록 기록을 찾지 못했습니다. 다른 프로젝트를 추측하지 않았습니다.",
                    testedAt: timestamp)
            }
            var request = URLRequest(url: URL(string: base + "/api/chat")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "text": "자비스, 다음 할 일 뭐야?",
                "remote_consent": false
            ])
            let (chatData, chatResponse) = try await session.data(for: request)
            guard (chatResponse as? HTTPURLResponse)?.statusCode == 200 else {
                return JarvisRoundTripFinding(
                    passed: false,
                    detail: "로컬 텍스트 명령에 정상적인 HTTP 응답이 없습니다. 실제 음성 기능은 확인하지 않았습니다.",
                    testedAt: timestamp)
            }
            let reply = try JSONDecoder().decode(ChatReply.self, from: chatData)
            guard isConfirmed(reply, selfProjectFound: true) else {
                return JarvisRoundTripFinding(
                    passed: false,
                    detail: "명령 응답이 예상한 JARVIS 자기 프로젝트 기록과 일치하지 않습니다. 실행 결과를 성공으로 표시하지 않았습니다.",
                    testedAt: timestamp)
            }
            return JarvisRoundTripFinding(
                passed: true,
                detail: "Mac 네이티브 점검 코드 → localhost /api/projects → /api/chat 실제 텍스트 명령 왕복 검증 성공. " +
                        "응답의 프로젝트 출처·읽기 전용 실행 여부 확인. " +
                        "마이크 입력·음성 합성 재생·화면 캡처·버튼 조작 성공을 뜻하지 않습니다.",
                testedAt: timestamp)
        } catch {
            return JarvisRoundTripFinding(
                passed: false,
                detail: "로컬 명령 왕복 점검 실패: \(error.localizedDescription). 음성·UI는 미검증입니다.",
                testedAt: timestamp)
        }
    }
}
