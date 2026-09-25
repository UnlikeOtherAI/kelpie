import Foundation

/// Credentials never enter renderer cookies, disk caches, redirect targets or logs.
final class UOATransport: NSObject, URLSessionTaskDelegate {
    static let origin = "https://authentication.unlikeotherai.com"
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    struct Response {
        let data: Data
        let version: String?
    }

    struct Failure: LocalizedError {
        let status: Int
        var errorDescription: String? {
            switch status {
            case 401: return "Your UOA session has expired. Sign in again."
            case 403: return "Your UOA account did not grant access to favourites."
            case 409: return "Favourites changed on another device. Please try again."
            default: return "UOA could not complete this request (\(status)). Please try again."
            }
        }
    }

    func request(_ path: String, method: String = "GET", token: String? = nil, body: Data? = nil, version: String? = nil) async throws -> Response {
        guard path.hasPrefix("/oauth/"), !path.contains(".."),
              let url = URL(string: Self.origin + path), url.host == "authentication.unlikeotherai.com" else {
            throw Failure(status: 400)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let version { request.setValue(version, forHTTPHeaderField: "If-Match") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure(status: 0) }
        guard (200..<300).contains(response.statusCode) else { throw Failure(status: response.statusCode) }
        return Response(data: data, version: response.value(forHTTPHeaderField: "ETag"))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
