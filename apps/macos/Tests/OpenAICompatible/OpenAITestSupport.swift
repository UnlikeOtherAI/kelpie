import Foundation
@testable import Kelpie

/// Scripted HTTP transport. Each request is answered by `handler`; streamed
/// bodies are cut into random small chunks to exercise chunk boundaries.
final class FakeOpenAITransport: OpenAIHTTPTransport, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body = Data()
        var error: Error?
        /// Never finish the stream (used for cancellation tests).
        var hang = false
    }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var handler: (URLRequest) -> Reply
    var maxChunk = 5

    init(handler: @escaping (URLRequest) -> Reply) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    private func record(_ request: URLRequest) -> Reply {
        lock.lock()
        _requests.append(request)
        lock.unlock()
        return handler(request)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = record(request)
        if let error = reply.error { throw error }
        return (reply.body, response(for: request, reply: reply))
    }

    func stream(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<[UInt8], Error>) {
        let reply = record(request)
        if let error = reply.error { throw error }
        let bytes = [UInt8](reply.body)
        let maxChunk = maxChunk
        let stream = AsyncThrowingStream<[UInt8], Error> { continuation in
            let task = Task {
                var index = 0
                while index < bytes.count {
                    let size = Int.random(in: 1...max(1, maxChunk))
                    let end = min(bytes.count, index + size)
                    continuation.yield(Array(bytes[index..<end]))
                    index = end
                    await Task.yield()
                }
                if reply.hang {
                    while !Task.isCancelled { try? await Task.sleep(nanoseconds: 10_000_000) }
                    continuation.finish(throwing: CancellationError())
                    return
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (response(for: request, reply: reply), stream)
    }

    private func response(for request: URLRequest, reply: Reply) -> HTTPURLResponse {
        // swiftlint:disable:next force_unwrapping
        HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
    }
}

final class InMemorySecrets: OpenAISecretStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    func get(_ name: String) -> String? { values[name] }
    func set(_ name: String, value: String) { values[name] = value }
    func remove(_ name: String) { values.removeValue(forKey: name) }
    var all: [String: String] { values }
}

final class RecordingDispatcher: OpenAIToolDispatching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(method: String, body: [String: Any])] = []
    var reply: (String, [String: Any]) -> [String: Any] = { _, _ in ["success": true] }

    var calls: [(method: String, body: [String: Any])] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func dispatch(method: String, body: [String: Any]) async -> [String: Any] {
        record(method: method, body: body)
        return reply(method, body)
    }

    /// Synchronous so the lock is never held across a suspension point.
    private func record(method: String, body: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        _calls.append((method, body))
    }
}

enum OpenAIFixtures {
    static func json(_ object: Any) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func sse(_ events: [Any], done: Bool = true, keepAlive: Bool = true) -> Data {
        var text = ""
        for (index, event) in events.enumerated() {
            if keepAlive && index == 1 { text += ": keep-alive\r\n\r\n" }
            let payload = String(bytes: json(event), encoding: .utf8) ?? ""
            text += "data: \(payload)\r\n\r\n"
        }
        if done { text += "data: [DONE]\n\n" }
        return Data(text.utf8)
    }

    static func chunk(_ delta: [String: Any], finish: String? = nil) -> [String: Any] {
        [
            "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": delta, "finish_reason": finish.map { $0 as Any } ?? NSNull()]]
        ]
    }

    static func toolCallStream(name: String, arguments: String, id: String = "call_1") -> Data {
        var events: [Any] = [chunk(["role": "assistant", "content": ""])]
        events.append(chunk(["reasoning_content": "I should look at the page."]))
        events.append(chunk(["tool_calls": [["index": 0, "id": id, "type": "function", "function": ["name": name, "arguments": ""]]]]))
        for piece in arguments.map(String.init) {
            events.append(chunk(["tool_calls": [["index": 0, "function": ["arguments": piece]]]]))
        }
        events.append(chunk([:], finish: "tool_calls"))
        return sse(events)
    }

    static func answerStream(_ text: String, reasoning: String = "") -> Data {
        var events: [Any] = [chunk(["role": "assistant"])]
        if !reasoning.isEmpty { events.append(chunk(["reasoning_content": reasoning])) }
        events.append(contentsOf: text.map { chunk(["content": String($0)]) })
        events.append(chunk([:], finish: "stop"))
        events.append(["choices": [], "usage": ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15]])
        return sse(events)
    }

    static let strataModels: [String: Any] = [
        "object": "list",
        "data": [[
            "id": "qwen3.8-flash-next-ud-q4_k_xl",
            "object": "model",
            "status": ["value": "loaded"],
            "meta": ["n_ctx": 131_072],
            "architecture": ["input_modalities": ["text"], "output_modalities": ["text"]]
        ]]
    ]

    static func service(transport: FakeOpenAITransport, secrets: InMemorySecrets = InMemorySecrets()) -> OpenAIEndpointService {
        let suite = "kelpie.tests.openai.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suite)!
        return OpenAIEndpointService(
            persistence: OpenAIEndpointPersistence(defaults: defaults),
            secrets: secrets,
            transport: transport
        )
    }
}
