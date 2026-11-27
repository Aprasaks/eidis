import SwiftUI

struct JARVISCalendarPairingView: View {
    @ObservedObject var nearby: JARVISMobileNearbyCalendar
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 13) {
                        Image(systemName: (nearby.connected || nearby.remoteProjectVerified) ? "checkmark.circle.fill" : "laptopcomputer")
                            .font(.system(size: 29, weight: .light))
                            .foregroundStyle(JARVISPalette.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nearby.connectionSummary)
                                .font(.headline)
                            Text(nearby.connected ? nearby.status : nearby.remoteStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if nearby.remembered {
                    Section("연결 방식") {
                        Toggle("Tailscale 원격 전용 테스트", isOn: Binding(
                            get: { nearby.remoteOnly }, set: { nearby.setRemoteOnly($0) }))
                            .disabled(nearby.publishing)
                        Text(nearby.remoteOnly ? "근거리 연결을 일시 중지합니다. 원격 조회 및 승인 발행을 시험합니다. 일정 동기화는 근거리 연결이 필요합니다." : "자동 연결 · 근거리 우선, 실패하면 원격 조회")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(nearby.remoteStatus).font(.footnote)
                        Button("프로젝트 다시 조회") { nearby.refreshProjects() }
                    }
                }

                if nearby.connected {
                    Section {
                        Button {
                            nearby.sync()
                        } label: {
                            Label(nearby.syncing ? "일정 확인 중" : "지금 동기화",
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(nearby.syncing)
                        Button("기기 등록 해제", role: .destructive) {
                            nearby.disconnect()
                        }
                    }
                } else if nearby.remembered {
                    Section {
                        Text("Mac 이디스가 실행 중이어야 합니다. 외부에서는 두 기기의 Tailscale 연결을 확인하세요.")
                            .font(.footnote)
                        Button("다시 연결 시도") { nearby.setForeground(true); nearby.refreshProjects() }
                        Button("기기 등록 해제", role: .destructive) { nearby.disconnect() }
                    }
                } else {
                    Section {
                        Text("맥 이디스의 캘린더에서 'iPhone 연결'을 누르고 표시된 코드를 입력하세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("연결 코드 12자리", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .onChange(of: code) { _, value in
                                code = String(value.filter(\.isNumber).prefix(12))
                            }
                        Button {
                            nearby.startSearch()
                        } label: {
                            Label(nearby.searching ? "Mac 다시 검색" : "근처 Mac 찾기",
                                  systemImage: "antenna.radiowaves.left.and.right")
                        }
                    } header: {
                        Text("연결하기")
                    }
                    if !nearby.peers.isEmpty {
                        Section("근처 기기") {
                            ForEach(nearby.peers, id: \.self) { peer in
                                Button {
                                    nearby.invite(peer, code: code)
                                } label: {
                                    HStack {
                                        Image(systemName: "desktopcomputer")
                                        Text(peer.displayName)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .disabled(code.count != 12)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(JARVISPalette.black)
            .navigationTitle("기기 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(JARVISPalette.gold)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
