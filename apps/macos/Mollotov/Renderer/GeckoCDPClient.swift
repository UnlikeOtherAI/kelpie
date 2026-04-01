import Foundation

/// Minimal CDP (Chrome DevTools Protocol) client over WebSocket.
/// Used to drive Firefox via its Remote Debugging Protocol.
@MainActor
final class GeckoCDPClient: NSObject, URLSessionWebSocketDelegate {
    typealias EventHandler = ([String: Any]) -> Void

    private var task: URLSessionWebSocketTask?
    private var nextId: Int = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var eventHandlers: [String: [EventHandler]] = [:]
    private var session: URLSession?

    enum CDPError: Error {
        case noConnection
        case commandFailed(String)
        case malformedResponse
    }

    func connect(port: Int) async throws {
        let wsURL = try await resolveWebSocketURL(port: port)
        let config = URLSessionConfiguration.default
        let sess = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = sess
        let ws = sess.webSocketTask(with: wsURL)
        task = ws
        ws.resume()
        startReceiveLoop()
    }

    func disconnect() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        for (_, cont) in pending {
            cont.resume(throwing: CDPError.noConnection)
        }
        pending.removeAll()
    }

    @discardableResult
    func send(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let task else { throw CDPError.noConnection }
        let id = nextId
        nextId += 1
        var message: [String: Any] = ["id": id, "method": method]
        if !params.isEmpty { message["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: message)
        let string = String(data: data, encoding: .utf8)!
        try await task.send(.string(string))
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
        }
    }

    func on(_ method: String, handler: @escaping EventHandler) {
        eventHandlers[method, default: []].append(handler)
    }

    private func resolveWebSocketURL(port: Int) async throws -> URL {
        let url = URL(string: "http://127.0.0.1:\(port)/json/list")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        let sess = URLSession(configuration: cfg)
        // /json/list may not be ready immediately after /json/version
        for attempt in 0..<10 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let (data, resp) = try? await sess.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = array.first,
                  let wsURLString = first["webSocketDebuggerUrl"] as? String,
                  let wsURL = URL(string: wsURLString) else { continue }
            NSLog("[GeckoCDPClient] connected after %d attempts", attempt + 1)
            return wsURL
        }
        throw CDPError.malformedResponse
    }

    private func startReceiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.handleMessage(message)
                    self.startReceiveLoop()
                }
            case .failure(let error):
                NSLog("[GeckoCDPClient] WebSocket error: %@", error.localizedDescription)
                Task { @MainActor in
                    for (_, cont) in self.pending {
                        cont.resume(throwing: error)
                    }
                    self.pending.removeAll()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let string: String
        switch message {
        case .string(let s): string = s
        case .data(let d): string = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let id = json["id"] as? Int, let cont = pending.removeValue(forKey: id) {
            if let error = json["error"] as? [String: Any],
               let msg = error["message"] as? String {
                cont.resume(throwing: CDPError.commandFailed(msg))
            } else {
                cont.resume(returning: json["result"] as? [String: Any] ?? [:])
            }
            return
        }
        if let method = json["method"] as? String,
           let params = json["params"] as? [String: Any] {
            eventHandlers[method]?.forEach { $0(params) }
        }
    }
}
