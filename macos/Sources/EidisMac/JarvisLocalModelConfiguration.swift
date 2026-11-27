import Foundation

/// The 27B model was removed after confirmed RAM pressure on a 24GB Mac.
/// All JARVIS Ollama call sites now use the verified 9B model only.
enum JarvisLocalModelConfiguration {
    static let defaultModel = "qwen3.5:9b-q4_K_M"
    static var selectedModel: String { defaultModel }
    // Every Ollama call must send the same num_ctx: a different value makes
    // Ollama reload the model (measured 1.2-1.5s per switch on this Mac).
    static let contextLength = 6144
    // Keep Qwen resident between sparse work-time questions (cold load ~6s).
    static let keepAlive = "30m"
}
