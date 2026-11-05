import Foundation

enum HTTPContentLength {
    enum Result {
        case valid(Int)
        case missing
        case malformed
    }

    /// Strictly parses the `Content-Length` header. Rejects negatives,
    /// non-integer values, and trailing garbage. RFC 7230 §3.3.2 requires
    /// a non-negative decimal — `Int("-1")` parses successfully and used to
    /// pass through as a body-size of -1, making `bodyReceived >= -1` always
    /// true and short-circuiting the read loop.
    static func parse(_ headers: String) -> Result {
        for line in headers.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let parsed = Int(value) else {
                return .malformed
            }
            return .valid(parsed)
        }
        return .missing
    }

}
