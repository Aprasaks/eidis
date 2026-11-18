import Foundation

/// A handoff snapshot built only from already-loaded user task records,
/// the LAST explicitly approved public GitHub read, and the LAST manually
/// requested local Git read. Never initiates I/O or infers deployment state.
struct JarvisHandoffReport {
    let projectId: Int
    let createdAt: Date
    let body: String

    static func make(project: WorkProject,
                     localFolderConnected: Bool,
                     localEvidence: LocalGitEvidence?,
                     createdAt: Date = Date()) -> JarvisHandoffReport {
        var lines: [String] = []
        lines.append("프로젝트 인수인계 · \(project.name)")
        lines.append("요약 생성: \(dateString(createdAt))")
        lines.append("프로젝트 ID: \(project.id)")
        lines.append("목표 (사용자 기록): \(project.goal.isEmpty ? "미입력" : project.goal)")
        lines.append("")
        lines.append("1. 작업 현황 · 사용자가 기록한 상태")
        let counts = project.taskCounts
        lines.append("예정 \(counts.todo) · 진행 \(counts.doing) · 막힘 \(counts.blocked) · 완료 \(counts.done)")
        if project.nextTasks.isEmpty {
            lines.append("다음 이어 할 일: 등록된 진행/예정 작업 없음 (실제 완료 여부 미검증)")
        } else {
            lines.append("다음 이어 할 일 (진행 중 우선, 최대 5개):")
            for task in project.nextTasks {
                lines.append(" - [\(task.status == "doing" ? "진행" : "예정")] \(task.title)")
            }
        }
        if project.blockedTasks.isEmpty {
            lines.append("막힌 작업: 기록 없음")
        } else {
            lines.append("막힌 작업 (최대 5개):")
            for task in project.blockedTasks.prefix(5) {
                lines.append(" - [막힘] \(task.title)")
            }
            if project.blockedTasks.count > 5 {
                lines.append(" - 이 외 \(project.blockedTasks.count - 5)개")
            }
        }
        lines.append("")
        lines.append("2. Mac 로컬 Git · 명시적 수동 확인 결과")
        if !localFolderConnected {
            lines.append("확인 불가: 이 프로젝트에 연결된 Mac 폴더 없음")
        } else if let snapshot = localEvidence {
            lines.append("마지막 직접 조회: \(dateString(snapshot.checkedAt)) (현재 시점 재검사 아님)")
            lines.append("브랜치: \(snapshot.branch)")
            lines.append("HEAD: \(snapshot.headSHA)")
            lines.append("Git 변경 항목: 추적 \(snapshot.changedTrackedEntries), 미추적 \(snapshot.untrackedEntries)")
            lines.append(snapshot.isDirty
                ? "주의: 당시 로컬 작업 폴더에 변경 항목이 있었음"
                : "당시 Git status 기준 변경 항목 없음 (배포/원격 동기화 증거 아님)")
        } else {
            lines.append("폴더는 연결됐지만 이번 실행에서 Git 상태 확인 기록이 없음")
            lines.append("'현재 코드 상태 한 번 확인'을 직접 누른 뒤 다시 확인해야 함")
        }
        lines.append("")
        lines.append("3. 공개 GitHub · 마지막 승인 조회 기록")
        if let github = project.lastCheck {
            lines.append("조회 시각: \(github.checkedAt) (현재 시점 조회 아님)")
            lines.append("연결 저장소: \(project.repoFullName.isEmpty ? "미지정" : project.repoFullName)")
            lines.append("기본 브랜치: \(github.branch)")
            lines.append("마지막 확인 HEAD: \(github.headSha)")
            if github.workflowState == "unavailable" {
                lines.append("Workflow: 당시 HEAD와 일치하는 실행 증거를 확인하지 못함")
            } else {
                lines.append("Workflow: \(github.workflowState) / \(github.workflowConclusion) (마지막 조회 기록)")
            }
        } else {
            lines.append("확인 기록 없음. 승인 없는 GitHub 조회는 실행하지 않았음")
        }
        lines.append("")
        lines.append("4. 검증 경계와 이어서 할 일")
        lines.append("사용자 작업 기록, Mac Git 스냅샷, 공개 GitHub 확인 기록은 서로 다른 출처임")
        lines.append("Mac 폴더가 해당 GitHub 저장소와 동일한지 자동 검증하지 않음")
        lines.append("AWS 배포·사이트 공개·테스트 성공·작업 완료 여부는 이 요약만으로 검증 불가")
        lines.append("변경 작업·배포·외부 조회를 자동 실행하지 않았음")
        return JarvisHandoffReport(projectId: project.id, createdAt: createdAt,
                                   body: lines.joined(separator: "\n"))
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
