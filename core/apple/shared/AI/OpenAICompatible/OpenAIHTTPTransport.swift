import Foundation

/// Network seam for the OpenAI-compatible client so tests can inject fakes.
protocol OpenAIHTTPTransport: Sendable {
    /// Performs a request and returns the full body.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Performs a request and streams the body in arbitrary chunks.
    func stream(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<[UInt8], Error>)
}

/// URLSession transport that follows same-origin redirects only, so an
/// `Authorization` header can never be forwarded to another origin.
final class URLSessionOpenAITransport: NSObject, OpenAIHTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = URLSessionOpenAITransport()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 900
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenAIEndpointError.malformedResponse("not an HTTP response")
            }
            return (data, http)
        } catch {
            throw Self.map(error)
        }
    }

    func stream(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<[UInt8], Error>) {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw Self.map(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIEndpointError.malformedResponse("not an HTTP response")
        }
        let stream = AsyncThrowingStream<[UInt8], Error> { continuation in
            let pump = Task {
                var chunk: [UInt8] = []
                chunk.reserveCapacity(1_024)
                do {
                    for try await byte in bytes {
                        chunk.append(byte)
                        // Hand over complete lines promptly so deltas are not delayed.
                        if byte == 0x0A || chunk.count >= 1_024 {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
        return (http, stream)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest,
              let target = request.url,
              Self.shouldFollowRedirect(from: original.url, to: target) else {
            // Refuse: the 3xx response itself is delivered and reported.
            completionHandler(nil)
            return
        }
        var followed = original
        followed.url = target
        completionHandler(followed)
    }

    /// Only same-origin (scheme, host and port) redirects are followed, so
    /// credentials never travel to a different origin.
    static func shouldFollowRedirect(from source: URL?, to target: URL?) -> Bool {
        guard let source, let target,
              let from = OpenAIEndpointURL.origin(of: source),
              let to = OpenAIEndpointURL.origin(of: target) else { return false }
        return from == to
    }

    static func map(_ error: Error) -> Error {
        if error is OpenAIEndpointError { return error }
        if error is CancellationError { return OpenAIEndpointError.cancelled }
        guard let urlError = error as? URLError else {
            return OpenAIEndpointError.unreachable(error.localizedDescription)
        }
        switch urlError.code {
        case .cancelled: return OpenAIEndpointError.cancelled
        case .timedOut: return OpenAIEndpointError.timeout
        default: return OpenAIEndpointError.unreachable(urlError.localizedDescription)
        }
    }
}
