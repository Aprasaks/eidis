import Foundation

/// Keeps local Qwen weights resident while the app runs. No generation, no
/// text, no account credentials and no remote provider. An unavailable Ollama
/// is fine.
///
/// - start(): preload once, then refresh keep_alive every `heartbeatInterval`
///   so Qwen stays loaded through long quiet stretches of work.
/// - warmNow(): extra preload when the wake word fires (Qwen may have been
///   unloaded by memory pressure or by another Ollama client).
/// - stop(): unload immediately on a normal quit. If the app crashes instead,
///   the last keep_alive (30m) lets Ollama unload on its own.
@MainActor
final class JarvisLocalModelWarmup {
    /// Must stay shorter than JarvisLocalModelConfiguration.keepAlive (30m).
    static let heartbeatInterval: Duration = .seconds(10*60)

    private var heartbeat: Task<Void,Never>?
    private var inFlight: Task<Void,Never>?
    private var stopped=false

    func start() {
        guard heartbeat==nil && !stopped else { return }
        heartbeat=Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.stopped else { return }
                await self.warm()
                do { try await Task.sleep(for: Self.heartbeatInterval) } catch { return }
            }
        }
    }

    func warmNow() {
        guard !stopped, inFlight==nil else { return }
        inFlight=Task { [weak self] in
            await self?.warm()
            self?.inFlight=nil
        }
    }

    private func warm() async {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState != .serious,
              ProcessInfo.processInfo.thermalState != .critical else { return }
        let started=Date()
        let selectedModel = JarvisLocalModelConfiguration.selectedModel
        var request=URLRequest(url:URL(string:"http://127.0.0.1:11434/api/generate")!)
        request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.timeoutInterval=45
        request.httpBody=try? JSONSerialization.data(withJSONObject:[
            "model":selectedModel,
            "stream":false,
            "keep_alive": JarvisLocalModelConfiguration.keepAlive,
            "options":["num_ctx":JarvisLocalModelConfiguration.contextLength]
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

    func stop() {
        stopped=true
        heartbeat?.cancel()
        heartbeat=nil
        inFlight?.cancel()
        inFlight=nil
        Self.unloadBlocking()
    }

    /// Called from applicationWillTerminate, so it waits briefly (max 1.5s)
    /// for Ollama to accept the unload before the process exits.
    private static func unloadBlocking() {
        var request=URLRequest(url:URL(string:"http://127.0.0.1:11434/api/generate")!)
        request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.timeoutInterval=1.5
        request.httpBody=try? JSONSerialization.data(withJSONObject:[
            "model":JarvisLocalModelConfiguration.selectedModel,
            "keep_alive":0
        ])
        let done=DispatchSemaphore(value:0)
        URLSession.shared.dataTask(with:request) { _,_,_ in done.signal() }.resume()
        _ = done.wait(timeout:.now()+1.5)
        NSLog("DECHIVE local Ollama unload requested on quit")
    }
}
