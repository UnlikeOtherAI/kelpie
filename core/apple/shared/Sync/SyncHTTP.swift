import Foundation
import Network

/// The request line and headers of one sync request. Header names are lower-cased.
struct SyncHTTPHead {
    let method: String
    let path: String
    let headers: [String: [String]]

    static let terminator = Data("\r\n\r\n".utf8)

    static func parse(_ data: Data) -> Self? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ", omittingEmptySubsequences: false) ?? []
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return nil }
        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { return nil }
            headers[name, default: []].append(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        return Self(method: String(parts[0]), path: String(parts[1]), headers: headers)
    }

    func value(_ name: String) -> String? {
        guard let values = headers[name], values.count == 1 else { return nil }
        return values[0]
    }

    /// A single, strictly decimal Content-Length; nil when absent, duplicated or malformed.
    var contentLength: Int? {
        guard let raw = value("content-length"), !raw.isEmpty, raw.count <= 10,
              raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(raw)
    }
}

/// A sync response. Every response is JSON, `no-store` and closes the connection.
struct SyncHTTPResponse {
    let status: Int
    let body: Data

    static func json(_ status: Int, _ object: [String: Any]) -> Self {
        Self(status: status, body: (try? SyncJSON.data(object)) ?? Data("{}".utf8))
    }

    static func error(_ status: Int, _ code: String) -> Self { json(status, ["error": code]) }

    func render() -> Data {
        var header = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        header += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

    /// Parses a complete response; nil until the head and the declared body have arrived.
    static func parse(_ data: Data, complete: Bool) -> Self? {
        guard let end = data.range(of: SyncHTTPHead.terminator),
              let text = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/1."), let status = Int(parts[1]) else { return nil }
        let body = data[end.upperBound...]
        let length = lines.dropFirst().compactMap { line -> Int? in
            guard line.lowercased().hasPrefix("content-length:") else { return nil }
            return Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
        }.first
        if let length {
            guard body.count >= length else { return nil }
            return Self(status: status, body: Data(body.prefix(length)))
        }
        return complete ? Self(status: status, body: Data(body)) : nil
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }
}

/// Network failures of the sync client. Codes are what status reports.
struct SyncNetworkError: Error, Equatable {
    let code: String

    static let timeout = Self(code: "TIMEOUT")
    static let unreachable = Self(code: "UNREACHABLE")
    static let addressRejected = Self(code: "ADDRESS_REJECTED")
    static let malformed = Self(code: "PROTOCOL")
}

enum SyncNetwork {
    static let queue = DispatchQueue(label: "com.unlikeotherai.kelpie.sync.network")
    static let maxResponseBytes = 4 * 1024 * 1024 + 64 * 1024
}
