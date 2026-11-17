import Foundation

let project = WorkProject(
    id: 7, name: "가상 테스트 프로젝트", goal: "검색 오류를 이해하고 정리",
    repoFullName: "example/demo",
    tasks: [
        WorkTask(id: 21, title: "검색 오류 원인 점검", status: "doing"),
        WorkTask(id: 22, title: "결과 성능 측정", status: "todo"),
        WorkTask(id: 23, title: "완료된 화면", status: "done")
    ],
    taskCounts: WorkCounts(todo: 1, doing: 1, blocked: 0, done: 1),
    lastCheck: nil
)
let evidence = LocalGitEvidence(
    rootPath: "/Users/SECRET-PATH/project",
    branch: "test-branch", headSHA: String(repeating: "a", count: 40),
    changedTrackedEntries: 2, untrackedEntries: 1,
    checkedAt: Date(timeIntervalSince1970: 1_700_000_000)
)
let snapshot = try JarvisLocalPlanning.snapshot(
    project: project, localFolderConnected: true,
    localEvidence: evidence, openedNote: "SECRET NOTE",
    openedNoteProjectId: 99, openedNoteTaskId: 21
)
precondition(snapshot.taskId == 21)
precondition(snapshot.taskStatus == "doing")
precondition(snapshot.sourceText.contains("검색 오류 원인 점검"))
precondition(snapshot.sourceText.contains("test-branch"))
precondition(snapshot.sourceText.contains("Git 변경 항목: 추적 2, 미추적 1"))
precondition(!snapshot.sourceText.contains("SECRET-PATH"))
precondition(!snapshot.sourceText.contains("SECRET NOTE"))
precondition(!snapshot.sourceIncludesOpenedNote)
precondition(snapshot.stillMatches(project))
let opened = try JarvisLocalPlanning.snapshot(
    project: project, localFolderConnected: false, localEvidence: nil,
    openedNote: "사용자가 직접 연 메모",
    openedNoteProjectId: 7, openedNoteTaskId: 21
)
precondition(opened.sourceIncludesOpenedNote)
precondition(opened.sourceText.contains("사용자가 직접 연 메모"))
precondition(!opened.sourceText.contains("test-branch"))

let noNext = WorkProject(
    id: 7, name: project.name, goal: project.goal,
    repoFullName: project.repoFullName,
    tasks: [WorkTask(id: 23, title: "완료된 화면", status: "done")],
    taskCounts: WorkCounts(todo: 0, doing: 0, blocked: 0, done: 1),
    lastCheck: nil
)
do {
    _ = try JarvisLocalPlanning.snapshot(
        project: noNext, localFolderConnected: false, localEvidence: nil)
    preconditionFailure("expected no task failure")
} catch JarvisLocalPlanningError.noTask {}
precondition(!snapshot.stillMatches(noNext))
precondition(!JarvisLocalPlanning.availabilityDescription().isEmpty)
print("PASS v3.5 read-only planner snapshot, specific task, no leaked path or unrelated note")
