import Foundation

@main
struct PlannerLiveProbe {
    static func main() async {
        let project = WorkProject(
            id: 99, name: "가상 테스트 저장소", goal: "기능 검증",
            repoFullName: "example/demo",
            tasks: [
                WorkTask(id: 1, title: "로컬 검색 결과 빈 화면의 원인 확인", status: "doing"),
                WorkTask(id: 2, title: "검증 결과 문서화", status: "todo")
            ],
            taskCounts: WorkCounts(todo: 1, doing: 1, blocked: 0, done: 0),
            lastCheck: nil
        )
        do {
            let context = try JarvisLocalPlanning.snapshot(
                project: project, localFolderConnected: false, localEvidence: nil
            )
            let result = try await JarvisLocalPlanning.suggest(from: context)
            guard result.snapshot.taskId == 1, !result.suggestion.isEmpty else {
                fatalError("local model returned invalid context")
            }
            print("LOCAL_AI_MODEL_GENERATED_FOR_TEST_FIXTURE:")
            print(result.suggestion)
            print("PASS: local Apple Foundation Models integrated with stored-task context, no tool execution")
        } catch {
            print("LOCAL_AI_FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }
}
