import Foundation

/// Data shown on the native JARVIS home dashboard. There are no implied
/// live API reads: project metrics are populated only after /api/projects
/// successfully returned and local voice readiness only means Korean TTS.
struct JarvisSystemSnapshot: Equatable {
    enum ServerState: String {
        case checking, online, offline
        var label: String {
            switch self {
            case .checking: return "연결 확인 중"
            case .online: return "ONLINE"
            case .offline: return "연결 안 됨"
            }
        }
    }

    let server: ServerState
    let recordsLoaded: Bool
    let projectCount: Int
    let taskCount: Int
    let doingCount: Int
    let todoCount: Int
    let doneCount: Int
    let blockedCount: Int
    let nextTaskTitle: String?
    let nextTaskProject: String?
    let voiceOutputAvailable: Bool
    let appleModelState: String

    var memoryLabel: String {
        guard server == .online else { return "서버 연결 필요" }
        return recordsLoaded ? "로컬 기록 확인" : "기록 확인 전"
    }
    var voiceLabel: String {
        voiceOutputAvailable ? "한국어 출력 가능" : "한국어 출력 미확인"
    }
    var summaryLabel: String {
        switch server {
        case .checking: "로컬 서버 연결을 확인하고 있습니다."
        case .offline: "로컬 서버에 연결되지 않았습니다. 진단에서 상태를 확인하세요."
        case .online:
            recordsLoaded
            ? "로컬 작업 기록을 확인했습니다. 다음 작업은 아직 실행되지 않았습니다."
            : "서버는 연결됐지만 프로젝트 기록 확인이 필요합니다."
        }
    }

    static let initial = JarvisSystemSnapshot(
        server: .checking, recordsLoaded: false,
        projectCount: 0, taskCount: 0, doingCount: 0,
        todoCount: 0, doneCount: 0, blockedCount: 0,
        nextTaskTitle: nil, nextTaskProject: nil,
        voiceOutputAvailable: false,
        appleModelState: "기기 내 모델 미확인"
    )
}
