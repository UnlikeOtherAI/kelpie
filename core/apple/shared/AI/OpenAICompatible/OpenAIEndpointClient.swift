import Foundation

/// Speaks the OpenAI-compatible HTTP protocol to one endpoint:
/// `GET {base}/models` and `POST {base}/chat/completions`.
struct OpenAIEndpointClient: Sendable {
    let baseURL: OpenAIEndpointURL
    /// Optional. When nil or empty no `Authorization` header is sent.
    let apiKey: String?
    var transport: OpenAIHTTPTransport = URLSessionOpenAITransport.shared

    static let probeTimeout: TimeInterval = 8
    /// Applies to time-to-first-byte and to the idle gap between stream
    /// packets (`: keep-alive` comments reset it).
    static let generationTimeout: TimeInterval = 180

    // MARK: - Models

    func listModels() async throws -> [OpenAIModelInfo] {
        var request = makeRequest(operation: "models", method: "GET", timeout: Self.probeTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        if let error = mapStatus(response, body: data, operation: .models) { throw error }
        do {
            return try OpenAIModelListParser.parse(data)
        } catch {
            throw OpenAIEndpointError.malformedResponse("GET /models did not return a model list")
        }
    }

    // MARK: - Chat

    /// Runs one chat completion. Streaming is used by default so long
    /// generations keep the connection alive; the result is identical.
    func chat(
        body: [String: Any],
        stream: Bool = true,
        timeout: TimeInterval = Self.generationTimeout
    ) async throws -> OpenAIChatResult {
        var payload = body
        payload["stream"] = stream
        var request = makeRequest(operation: "chat/completions", method: "POST", timeout: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        if !stream {
            let (data, response) = try await transport.data(for: request)
            if let error = mapStatus(response, body: data, operation: .chat) { throw error }
            return try OpenAIChatAccumulator.parseCompletion(data)
        }

        let (response, chunks) = try await transport.stream(for: request)
        guard (200..<300).contains(response.statusCode) else {
            var body = Data()
            for try await chunk in chunks where body.count < 8_192 { body.append(contentsOf: chunk) }
            throw mapStatus(response, body: body, operation: .chat)
                ?? OpenAIEndpointError.server(status: response.statusCode, message: "unexpected status")
        }
        if !Self.isEventStream(response) {
            // Some servers ignore `stream: true` and answer with plain JSON.
            var body = Data()
            for try await chunk in chunks { body.append(contentsOf: chunk) }
            return try OpenAIChatAccumulator.parseCompletion(body)
        }
        return try await Self.consume(chunks)
    }

    /// Feeds a byte stream through the SSE parser and accumulator.
    static func consume(_ chunks: AsyncThrowingStream<[UInt8], Error>) async throws -> OpenAIChatResult {
        var parser = ServerSentEventParser()
        var accumulator = OpenAIChatAccumulator()
        for try await chunk in chunks {
            try Task.checkCancellation()
            for event in parser.feed(chunk) where try accumulator.apply(eventData: event.data) {
                return accumulator.result()
            }
        }
        for event in parser.finish() where try accumulator.apply(eventData: event.data) {
            return accumulator.result()
        }
        try Task.checkCancellation()
        guard accumulator.isComplete else { throw OpenAIEndpointError.streamTruncated }
        return accumulator.result()
    }

    // MARK: - Helpers

    private enum Operation { case models, chat }

    private func makeRequest(operation: String, method: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: baseURL.url(for: operation))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func mapStatus(_ response: HTTPURLResponse, body: Data, operation: Operation) -> OpenAIEndpointError? {
        let status = response.statusCode
        switch status {
        case 200..<300:
            return nil
        case 300..<400:
            let location = response.value(forHTTPHeaderField: "Location")
                .flatMap { URL(string: $0, relativeTo: response.url) }
                .flatMap { OpenAIEndpointURL.origin(of: $0.absoluteURL) } ?? "unknown location"
            return .redirectRefused(location)
        case 401, 403:
            return .authFailed
        case 404 where operation == .models, 405 where operation == .models, 501 where operation == .models:
            return .discoveryUnsupported
        case 503 where operation == .models:
            return .loading(OpenAIEndpointError.sanitizedServerMessage(body, apiKey: apiKey))
        default:
            return .server(status: status, message: OpenAIEndpointError.sanitizedServerMessage(body, apiKey: apiKey))
        }
    }

    private static func isEventStream(_ response: HTTPURLResponse) -> Bool {
        let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        return type.isEmpty || type.contains("text/event-stream")
    }
}
