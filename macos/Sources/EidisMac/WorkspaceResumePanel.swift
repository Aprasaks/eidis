import SwiftUI

/// Keeps user-controlled workflow confirmation isolated from the larger
/// project editing view. No action runs on view appear or state changes.
struct WorkspaceResumePanel: View {
    let project: WorkProject
    @ObservedObject var work: ApprovedWorkModel
    let requestedWorkspace: JarvisWorkspaceCommand?
    @State private var workspaceOpenFolder = false
    @State private var workspaceOpenGitHub = false
    @State private var workspaceProposal: JarvisWorkspaceProposal?
    @State private var workspaceConfirmVisible = false

    private func applyRoutedRequest() {
        guard let request = requestedWorkspace,
              request.projectId == project.id,
              request.projectName == project.name,
              request.repository == project.repoFullName else { return }
        let connected = work.localFolder(projectId: project.id) != nil
        switch request.destination {
        case .choose:
            workspaceOpenFolder = connected
            workspaceOpenGitHub = !connected && JarvisWorkspaceResume.githubURL(for: project.repoFullName) != nil
        case .github:
            workspaceOpenFolder = false
            workspaceOpenGitHub = true
        case .folder:
            workspaceOpenFolder = true
            workspaceOpenGitHub = false
        }
        workspaceProposal = JarvisWorkspaceResume.prepare(
            project: project,
            linkedFolder: work.localFolder(projectId: project.id),
            openFolder: workspaceOpenFolder,
            openGitHub: workspaceOpenGitHub)
    }

    var body: some View {
        GroupBox("작업 이어하기 · 승인 후 Finder / GitHub 열기") {
            VStack(alignment: .leading, spacing: 10) {
                Text("연결된 폴더나 해당 GitHub 저장소를 열 수 있어요. 파일 수정·자동 커밋·코드 실행·배포는 하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Mac 프로젝트 폴더를 Finder에서 열기", isOn: Binding(
                    get: { workspaceOpenFolder },
                    set: { workspaceOpenFolder = $0; workspaceProposal = nil }
                ))
                    .disabled(work.busy || work.localFolder(projectId: project.id) == nil)
                Toggle("GitHub 저장소를 브라우저에서 열기", isOn: Binding(
                    get: { workspaceOpenGitHub },
                    set: { workspaceOpenGitHub = $0; workspaceProposal = nil }
                ))
                    .disabled(work.busy || JarvisWorkspaceResume.githubURL(for: project.repoFullName) == nil)
                if work.localFolder(projectId: project.id) == nil {
                    Text("Mac 폴더를 열려면 먼저 위에서 'Git 폴더 연결'을 눌러 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("작업 이어하기 제안 만들기") {
                    workspaceProposal = JarvisWorkspaceResume.prepare(
                        project: project,
                        linkedFolder: work.localFolder(projectId: project.id),
                        openFolder: workspaceOpenFolder,
                        openGitHub: workspaceOpenGitHub)
                }
                .disabled(work.busy || (!workspaceOpenFolder && !workspaceOpenGitHub))
                if let workspaceProposal {
                    Text(workspaceProposal.description)
                        .font(.caption)
                        .textSelection(.enabled)
                    Button("열기 작업 1회 승인 화면") {
                        workspaceConfirmVisible = true
                    }
                    .disabled(work.busy)
                }
                if let receipt = work.workspaceReceipt, receipt.projectId == project.id {
                    Text(receipt.summary)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { applyRoutedRequest() }
        .onChange(of: requestedWorkspace?.id) { _, _ in applyRoutedRequest() }
        .alert("선택한 프로젝트 작업 공간을 열까요?",
               isPresented: $workspaceConfirmVisible) {
            Button("승인하고 선택한 작업 공간 1회 열기") {
                guard let proposal = workspaceProposal else { return }
                workspaceProposal = nil
                work.openApprovedWorkspace(proposal)
            }
            Button("취소", role: .cancel) { workspaceProposal = nil }
        } message: {
            Text(workspaceProposal?.description ?? "승인할 대상이 없습니다.")
        }
    }
}
