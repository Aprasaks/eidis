import SwiftUI
import Combine

/// Core motion is supplied by the user's text-free Blender footage.
/// The two additional video segments come from the SAME 16-second recording.
/// The active effects never alter the existing player or store microphone PCM.
struct JarvisCoreReactiveEffects: View {
    @ObservedObject var dialogue: JarvisOverlayConversation
    @ObservedObject var wake: JarvisDekaWake
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wakeFlash = false

    /// Debug-only preview flags let us verify actual pixels without
    /// recording someone's voice or fabricating speech recognition.
    private var previewListening: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--jarvis-preview-listening")
        #else
        false
        #endif
    }
    private var previewSpeaking: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--jarvis-preview-speaking")
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.347, geometry.size.height * 0.636)
            ZStack {
                if dialogue.isListening || previewListening {
                    // The outer video section is cut from the supplied Blender
                    // recording, with the still-rotating central core masked.
                    JarvisEffectFilm(name: "JARVIS_Core_Input_Rings",
                                     screenSize: geometry.size, strength: 0.95)
                    JarvisContinuousRipples(diameter: diameter,
                                            amplitude: { previewListening ? 0.8 : dialogue.inputAmplitude },
                                            reducedMotion: reduceMotion)
                } else if (dialogue.isSpeaking && dialogue.soundOutputActive) || previewSpeaking {
                    JarvisEffectFilm(name: "JARVIS_Core_Output_Brush",
                                     screenSize: geometry.size, strength: 1.0)
                    JarvisSpeakingBrush(diameter: diameter,
                                        outputAmplitude: { previewSpeaking ? 0.8 : ElevenLabsVoiceService.shared.visualOutputAmplitude },
                                        reducedMotion: reduceMotion)
                } else if dialogue.isThinking || dialogue.isSpeaking {
                    JarvisThinkingGlow(diameter: diameter, reducedMotion: reduceMotion)
                } else if wake.armed && wake.status == "호출 대기 · Jarvis" {
                    Circle()
                        .stroke(Color(red: 0.98, green: 0.72, blue: 0.37).opacity(0.3), lineWidth: 1.7)
                        .frame(width: diameter * 1.06, height: diameter * 1.06)
                }

                if wakeFlash {
                    Circle()
                        .stroke(.yellow.opacity(0.94), lineWidth: 5)
                        .frame(width: diameter * 1.14, height: diameter * 1.14)
                        .shadow(color: .orange, radius: 25)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .onChange(of: wake.activationSequence) { _, _ in
            wakeFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                wakeFlash = false
            }
        }
        .accessibilityHidden(true)
    }
}

/// Composite ONLY the glow outside the original orbit, preventing duplicated
/// cores. The video uses a black background: screen blend removes black while
/// keeping Blender's actual luminous strokes and smoke.
private struct JarvisEffectFilm: View {
    let name: String
    let screenSize: CGSize
    let strength: Double

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                JarvisLoopingCore(videoURL: url, compact: false)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .mask {
                        RadialGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.60),
                            .init(color: .white, location: 0.84),
                            .init(color: .white, location: 1)
                        ], center: .center, startRadius: 0,
                                       endRadius: min(screenSize.width, screenSize.height) * 0.48)
                    }
                    .blendMode(.screen)
                    .opacity(strength)
            }
        }
    }
}

/// Four staggered, visibly expanding rings while speech capture is live.
/// Continuous time progression matters: a one-off activation flash is not a
/// substitute for seeing real speech input.
private struct JarvisContinuousRipples: View {
    let diameter: CGFloat
    let amplitude: () -> Double
    let reducedMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reducedMotion)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let loudness = min(1, max(0, amplitude()))
            let active = loudness > 0.017
            ZStack {
                if active {
                    ForEach(0..<4, id: \.self) { index in
                        let phase = (seconds / 1.55 + Double(index) / 4)
                            .truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(Color(red: 1, green: 0.73, blue: 0.31)
                                .opacity((1 - phase) * (0.55 + loudness * 0.43)),
                                lineWidth: 2.2 + loudness * 5.4)
                            .frame(width: diameter * (0.98 + phase * 0.99),
                                   height: diameter * (0.98 + phase * 0.99))
                            .shadow(color: .orange.opacity(0.60), radius: 12 + loudness * 17)
                    }
                }
                Circle()
                    .stroke(Color(red: 1, green: 0.82, blue: 0.47)
                        .opacity(active ? 0.65 + loudness * 0.35 : 0),
                        lineWidth: 2 + loudness * 4)
                    .frame(width: diameter * 1.05, height: diameter * 1.05)
                    .shadow(color: .orange.opacity(active ? 0.75 : 0), radius: 16)
            }
        }
    }
}

/// Bright painterly strokes and a diffuse gold cloud outside the ring.
/// ElevenLabs gives its actual output level; system TTS gives a constant
/// state-only level. This view exists only while audio IS playing.
private struct JarvisSpeakingBrush: View {
    let diameter: CGFloat
    let outputAmplitude: () -> Double?
    let reducedMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reducedMotion)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let volume = min(1, max(0.24, outputAmplitude() ?? 0.52))
            ZStack {
                Circle()
                    .stroke(Color(red: 1, green: 0.55, blue: 0.10)
                        .opacity(0.42 + volume * 0.30),
                        lineWidth: diameter * 0.10)
                    .frame(width: diameter * 1.38, height: diameter * 1.38)
                    .blur(radius: 30)

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for index in 0..<13 {
                        let n = Double(index)
                        let start = n * 31.0 + sin(seconds * 1.7 + n) * 10.0
                        let sweep = 17.0 + 17.0 * abs(sin(seconds * 1.2 + n))
                        let radius = diameter * (0.57 + CGFloat(n.truncatingRemainder(dividingBy: 4)) * 0.052)
                            + CGFloat(11 * sin(seconds * 1.4 + n * 0.77))
                        var brush = Path()
                        brush.addArc(center: center, radius: radius,
                                     startAngle: .degrees(start),
                                     endAngle: .degrees(start + sweep), clockwise: false)
                        let alpha = (0.53 + volume * 0.47) * (0.65 + 0.35 * abs(sin(seconds + n)))
                        context.stroke(brush,
                                       with: .color(Color(red: 1, green: 0.70, blue: 0.22)
                                           .opacity(alpha)),
                                       style: StrokeStyle(lineWidth: 3.2 + volume * 5.0,
                                                          lineCap: .round))
                    }
                }
                .frame(width: diameter * 2.05, height: diameter * 2.05)
                .shadow(color: .orange.opacity(0.75), radius: 16)

                Circle()
                    .stroke(Color(red: 1, green: 0.8, blue: 0.45)
                        .opacity(0.42 + volume * 0.45), lineWidth: 3.5)
                    .frame(width: diameter * 1.10, height: diameter * 1.10)
                    .shadow(color: .orange, radius: 21)
            }
        }
    }
}

private struct JarvisThinkingGlow: View {
    let diameter: CGFloat
    let reducedMotion: Bool
    @State private var rotated = false

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.78)
            .stroke(Color(red: 0.98, green: 0.70, blue: 0.33).opacity(0.48),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [20, 13]))
            .frame(width: diameter * 1.08, height: diameter * 1.08)
            .rotationEffect(.degrees(rotated ? 360 : 0))
            .onAppear {
                guard !reducedMotion else { return }
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotated = true
                }
            }
    }
}
