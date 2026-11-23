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
                        Image(systemName: nearby.connected ? "checkmark.circle.fill" : "laptopcomputer")
                            .font(.system(size: 29, weight: .light))
                            .foregroundStyle(JARVISPalette.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nearby.connected ? "Mac 연결됨" : "Mac 연결")
                                .font(.headline)
                            Text(nearby.status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
                        Button("연결 해제", role: .destructive) {
                            nearby.disconnect()
                        }
                    }
                } else {
                    Section {
                        Text("맥 자비스의 캘린더에서 'iPhone 연결'을 누르고 표시된 코드를 입력하세요.")
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
