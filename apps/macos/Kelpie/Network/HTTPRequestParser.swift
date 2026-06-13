import Foundation
import Network

/// Pure parser: turns a raw byte buffer + connection peer into a `ParsedHTTPRequest`.
/// Kept separate from `HTTPServer` so it stays focused and testable.
enum HTTPRequestParser {
    /// Attempt to parse a complete HTTP request out of `data`. Returns nil if
    /// the request line / headers are malformed beyond recovery.
    static func parse(data: Data, sourceAddress: String) -> ParsedHTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerString = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])

        let (path, query) = splitTarget(target)

        var headers: [String: [String]] = [:]
        var hasTransferEncoding = false
        for line in lines.dropFirst() {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let name = line[..<colonIdx].lowercased().trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            if name == "transfer-encoding" { hasTransferEncoding = true }
            headers[name, default: []].append(value)
        }

        let body = Data(data[headerEnd.upperBound...])

        return ParsedHTTPRequest(
            method: method,
            path: path,
            query: query,
            headers: headers,
            body: body,
            sourceAddress: sourceAddress,
            hasTransferEncoding: hasTransferEncoding
        )
    }

    /// Split "/v1/pair/status?requestId=abc" into ("/v1/pair/status", "requestId=abc").
    /// Percent-decodes the path so the auth allowlist is checked against the
    /// canonical decoded form.
    static func splitTarget(_ target: String) -> (path: String, query: String) {
        if let qIdx = target.firstIndex(of: "?") {
            let rawPath = String(target[..<qIdx])
            let query = String(target[target.index(after: qIdx)...])
            return (decodePath(rawPath), query)
        }
        return (decodePath(target), "")
    }

    private static func decodePath(_ raw: String) -> String {
        raw.removingPercentEncoding ?? raw
    }

    /// Extract a single query parameter value from the parsed query string.
    static func queryValue(_ name: String, in query: String) -> String? {
        guard !query.isEmpty else { return nil }
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.first == name {
                if kv.count == 2 {
                    return kv[1].removingPercentEncoding ?? kv[1]
                }
                return ""
            }
        }
        return nil
    }

    /// Render NWEndpoint into a printable address string. IPv4 is bare,
    /// IPv6 is wrapped in brackets to match URL conventions.
    static func formatSourceAddress(_ endpoint: NWEndpoint?) -> String {
        guard let endpoint else { return "unknown" }
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr): return "\(addr)"
            case .ipv6(let addr):
                // Strip zone identifier and bracket the address.
                let raw = "\(addr)"
                let trimmed = raw.split(separator: "%").first.map(String.init) ?? raw
                return "[\(trimmed)]"
            case .name(let name, _): return name
            @unknown default: return "unknown"
            }
        default:
            return "unknown"
        }
    }
}
