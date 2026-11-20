import SwiftUI

/// ElevenLabs account voice picker. GET voice metadata and provider preview URLs only.
/// Never enables paid TTS or exposes the API key.
struct JarvisElevenLabsLibraryView: View {
    @ObservedObject private var elevenLabs = ElevenLabsVoiceService.shared
    @State private var femalesOnly = false
    @State private var searchText = ""
    @State private var manualVoiceID = ""
    @State private var manualStatus = ""

    private var filtered: [ElevenLabsLibraryVoice] {
        elevenLabs.libraryVoices.filter { voice in
            (!femalesOnly || voice.gender.lowercased() == "female" || voice.gender == "미표시") &&
            (searchText.isEmpty || voice.name.localizedCaseInsensitiveContains(searchText) ||
             voice.accent.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("ElevenLabs · 내 라이브러리")
                .font(.system(size: 23, weight: .semibold))
            Text("ElevenLabs 계정에 저장된 목소리를 가져와 자비스에 적용합니다. 목록 조회와 선택은 음성 생성 크레딧을 쓰지 않습니다.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(elevenLabs.isLoadingLibrary ? "목록 가져오는 중…" : "내 ElevenLabs 목소리 불러오기") {
                    Task { await elevenLabs.fetchVoiceLibrary() }
                }
                .disabled(elevenLabs.isLoadingLibrary || elevenLabs.isBusy)
                Toggle("여성 목소리 우선", isOn: $femalesOnly)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            Text(elevenLabs.libraryStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            GroupBox("목록 조회가 안 된다면 · Voice ID 직접 연결") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("ElevenLabs 사이트에서 원하는 목소리의 Voice ID를 복사해 아래에 붙여넣으세요. 목소리 파일을 다운로드할 필요는 없습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("영문·숫자 20자리 Voice ID", text: $manualVoiceID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Voice ID 저장") {
                            let id = manualVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard id.range(of: "^[A-Za-z0-9]{20}$", options: .regularExpression) != nil else { return }
                            elevenLabs.voiceID = id
                            manualStatus = "ID 저장 완료 · 음성 합성 ON/OFF는 바꾸지 않았습니다."
                        }
                        .disabled(manualVoiceID.trimmingCharacters(in: .whitespacesAndNewlines).range(
                            of: "^[A-Za-z0-9]{20}$", options: .regularExpression) == nil)
                        Button("ID 접근 확인 · 음성 생성 없음") {
                            Task { await elevenLabs.checkVoiceConnection() }
                        }
                        .disabled(elevenLabs.isCheckingConnection || elevenLabs.isBusy)
                    }
                    Text("현재 선택 ID: \(elevenLabs.voiceID)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    if !manualStatus.isEmpty { Text(manualStatus).font(.caption) }
                    Text("연결 상태: " + elevenLabs.status)
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Voice ID 찾는 방법 · ElevenLabs 공식 안내", destination:
                         URL(string: "https://elevenlabs.io/docs/help-center/technical/how-do-i-find-the-voice-id-of-my-voices-via-the-website-and-api")!)
                        .font(.caption)
                }
                .padding(.vertical, 3)
            }
            TextField("목소리 이름·억양 검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
            List(filtered) { voice in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(voice.name).font(.headline)
                            if voice.id == elevenLabs.voiceID { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                        }
                        Text([voice.gender, voice.accent, voice.korean ? "한국어 검증 표시" : "한국어 미확인", voice.category]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("샘플 듣기") { elevenLabs.playLibrarySample(voice) }
                        .disabled(voice.sampleURL == nil)
                    Button(voice.id == elevenLabs.voiceID ? "선택됨" : "선택") {
                        elevenLabs.selectLibraryVoice(voice)
                    }
                    .disabled(voice.id == elevenLabs.voiceID)
                }
                .padding(.vertical, 4)
            }
            Text("선택은 저장되지만 ElevenLabs 자동 음성 생성은 켜지지 않습니다. 실제 자비스 답변에 사용하려면 '작업 및 설정 열기 → 음성'에서 활성화해 주세요. 음성 합성과 시험 합성은 ElevenLabs 크레딧을 사용할 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 560)
        .onAppear { manualVoiceID = elevenLabs.voiceID }
    }
}
