import Foundation

/// The 27B model was removed after confirmed RAM pressure on a 24GB Mac.
/// All JARVIS Ollama call sites now use the verified 9B model only.
enum JarvisLocalModelConfiguration {
    static let defaultModel = "qwen3.5:9b-q4_K_M"
    static var selectedModel: String { defaultModel }
}
