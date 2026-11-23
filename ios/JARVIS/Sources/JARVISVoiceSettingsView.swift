import SwiftUI

/// Private iPhone testing controls. API key never appears in the app binary
/// or a screenshot, and paid generation is explicitly disabled by default.
struct JARVISVoiceSettingsView: View {
    @ObservedObject var service: JARVISMobileElevenLabs
    @Environment(\.dismiss) private var dismiss
    @State private var enteredKey = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(JARVISPalette.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("목소리 설정").font(.headline)
                            Text("맥 자비스와 같은 ElevenLabs Voice ID")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("아이폰 자비스는 오라버니라고 부릅니다. 맥 자비스의 호칭과 목소리 설정은 변경하지 않아요.")
                        .font(.footnote)
                }

                Section("ElevenLabs 사용") {
                    Toggle("ElevenLabs 목소리로 답변", isOn: Binding(
                        get: { service.enabled },
                        set: { service.setEnabled($0) }
                    ))
                    .tint(JARVISPalette.gold)
                    .disabled(!service.isConfigured)
                    HStack {
                        Text("API 키")
                        Spacer()
                        Text(service.isConfigured ? "iPhone 키체인에 저장됨" : "설정 안 됨")
                            .foregroundStyle(.secondary)
                    }
                    Text(service.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if service.enabled {
                        Label("음성 생성마다 ElevenLabs 크레딧을 사용할 수 있어요.", systemImage: "creditcard")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("맥과 동일한 음색") {
                    TextField("Voice ID", text: $service.voiceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Picker("모델", selection: $service.modelID) {
                        Text("Flash v2.5 · 빠른 응답").tag("eleven_flash_v2_5")
                        Text("Multilingual v2").tag("eleven_multilingual_v2")
                    }
                    Text("Mac JARVIS에서 확인된 Voice ID와 Flash v2.5를 기본값으로 설정했습니다. Voice ID 자체는 비밀 키가 아니에요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await service.checkConnection() }
                    } label: {
                        HStack {
                            Text("음성 접근 확인 · 생성 비용 없음")
                            Spacer()
                            if service.isChecking { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(!service.isConfigured || service.isChecking || service.isGenerating)
                }

                Section("개인 테스트용 API 키") {
                    SecureField("ElevenLabs API 키 붙여넣기", text: $enteredKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("이 iPhone 키체인에 저장") {
                        if service.saveKey(enteredKey) {
                            enteredKey = ""
                        }
                    }
                    .disabled(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if service.isConfigured {
                        Button("저장된 API 키 삭제", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    Text("맥 키체인에 저장된 키는 iPhone에서 자동으로 읽을 수 없습니다. 키를 이 채팅에 보내지 마세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("개인 개발 앱의 임시 구성입니다. 외부 배포 전에는 iPhone에 장기 API 키를 저장하지 않고, 인증된 Mac 중계 서버 또는 단기 토큰으로 변경해야 합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JARVISPalette.black)
            .navigationTitle("음성")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(JARVISPalette.gold)
                }
            }
            .confirmationDialog("이 iPhone에 저장된 ElevenLabs 키를 삭제할까요?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("키 삭제", role: .destructive) { service.deleteKey() }
            }
            .preferredColorScheme(.dark)
        }
    }
}
