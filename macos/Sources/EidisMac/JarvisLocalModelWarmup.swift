import Foundation

/// Preload local Qwen weights once after app startup. No generation, no text,
/// no account credentials and no remote provider. An unavailable Ollama is fine.
@MainActor
final class JarvisLocalModelWarmup {
    private var task: Task<Void,Never>?
    private var stopped=false

    func start() {
        guard task==nil && !stopped,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else { return }
        task=Task {
            defer { task=nil }
            let started=Date()
            let selectedModel = JarvisLocalModelConfiguration.selectedModel
            var request=URLRequest(url:URL(string:"http://127.0.0.1:11434/api/generate")!)
            request.httpMethod="POST"
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.timeoutInterval=45
            request.httpBody=try? JSONSerialization.data(withJSONObject:[
                "model":selectedModel,
                "stream":false,
                "keep_alive":"2m"
            ])
            do {
                let config=URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest=45
                config.timeoutIntervalForResource=48
                let session=URLSession(configuration:config)
                defer {session.finishTasksAndInvalidate()}
                let (data,response)=try await session.data(for:request)
                guard !Task.isCancelled,!stopped,
                      (response as? HTTPURLResponse)?.statusCode==200,
                      data.count<5000,
                      let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                      object["model"] as? String == selectedModel
                else {return}
                NSLog("DECHIVE local Ollama weights ready preload_ms=%.1f",
                      Date().timeIntervalSince(started)*1000)
            } catch {
                // User can still use the non-LLM local tools without Ollama.
                NSLog("DECHIVE local Ollama preload unavailable")
            }
        }
    }

    func stop() {
        stopped=true
        task?.cancel()
        task=nil
    }
}
