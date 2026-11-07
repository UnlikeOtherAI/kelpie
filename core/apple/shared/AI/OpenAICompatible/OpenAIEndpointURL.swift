import Foundation

/// Validated, normalised base URL of an OpenAI-compatible server
/// (for example `http://127.0.0.1:18880/v1` or `https://host/openai/v1`).
///
/// Shared by macOS and iOS. Rules are defined in
/// docs/api/ai-endpoints.md → "URL handling".
struct OpenAIEndpointURL: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: Int?
    /// Base path without a trailing slash, always starting with `/`.
    let path: String

    enum ValidationError: Error, Equatable {
        case empty
        case unsupportedScheme
        case missingHost
        case invalidPort
        case userInfoNotAllowed
        case queryNotAllowed
        case malformed

        var message: String {
            switch self {
            case .empty: return "Enter the server's base URL, for example http://127.0.0.1:8080/v1."
            case .unsupportedScheme: return "The base URL must start with http:// or https://."
            case .missingHost: return "The base URL needs a host name or IP address."
            case .invalidPort: return "The port must be a number between 1 and 65535."
            case .userInfoNotAllowed: return "Do not put credentials in the URL. Use the API key field instead."
            case .queryNotAllowed: return "The base URL cannot contain a query string or fragment."
            case .malformed: return "The base URL is not a valid URL."
            }
        }
    }

    /// Operations people commonly paste together with the base URL.
    private static let operationSuffixes = ["/chat/completions", "/completions", "/models", "/embeddings"]
    static let defaultBasePath = "/v1"

    static func normalize(_ raw: String) throws -> Self {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }

        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else {
            throw ValidationError.unsupportedScheme
        }
        let port = try validatedPort(rawURL: trimmed)
        guard let components = URLComponents(string: trimmed) else { throw ValidationError.malformed }
        if components.user != nil || components.password != nil { throw ValidationError.userInfoNotAllowed }
        if components.query != nil || components.fragment != nil { throw ValidationError.queryNotAllowed }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ValidationError.unsupportedScheme
        }
        guard let rawHost = components.host, !rawHost.isEmpty else { throw ValidationError.missingHost }

        return Self(
            scheme: scheme,
            host: rawHost.lowercased(),
            port: port,
            path: normalizedPath(components.percentEncodedPath)
        )
    }

    /// Reads the port from the raw authority text so out-of-range or empty
    /// ports are rejected instead of being dropped by `URLComponents`.
    private static func validatedPort(rawURL: String) throws -> Int? {
        guard let schemeEnd = rawURL.range(of: "://") else { throw ValidationError.malformed }
        let afterScheme = rawURL[schemeEnd.upperBound...]
        let authority = afterScheme.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let hostAndPort = authority.split(separator: "@").last.map(String.init) ?? ""
        let portText: Substring?
        if hostAndPort.hasPrefix("[") {
            guard let close = hostAndPort.firstIndex(of: "]") else { throw ValidationError.malformed }
            let rest = hostAndPort[hostAndPort.index(after: close)...]
            portText = rest.hasPrefix(":") ? rest.dropFirst() : (rest.isEmpty ? nil : rest)
        } else if let colon = hostAndPort.lastIndex(of: ":") {
            portText = hostAndPort[hostAndPort.index(after: colon)...]
        } else {
            portText = nil
        }
        guard let portText else { return nil }
        guard let port = Int(portText), (1...65_535).contains(port) else { throw ValidationError.invalidPort }
        return port
    }

    private static func normalizedPath(_ rawPath: String) -> String {
        var segments = rawPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        var stripped = true
        while stripped {
            stripped = false
            for suffix in operationSuffixes where path.lowercased().hasSuffix(suffix) {
                path = String(path.dropLast(suffix.count))
                stripped = true
            }
        }
        segments = path.split(separator: "/").map(String.init)
        path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return path.isEmpty ? defaultBasePath : path
    }

    /// Canonical string form, e.g. `http://127.0.0.1:18880/v1`.
    var string: String {
        "\(scheme)://\(hostForURL)\(port.map { ":\($0)" } ?? "")\(path)"
    }

    /// Origin used for same-origin redirect checks.
    var origin: String {
        "\(scheme)://\(hostForURL):\(port ?? (scheme == "https" ? 443 : 80))"
    }

    /// Joins an operation such as `models` or `chat/completions`.
    func url(for operation: String) -> URL {
        let op = operation.split(separator: "/").joined(separator: "/")
        // swiftlint:disable:next force_unwrapping
        return URL(string: "\(string)/\(op)")!
    }

    /// True when the host is this device's loopback interface.
    var isLoopback: Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return bare == "localhost" || bare.hasSuffix(".localhost") || bare == "::1" || bare.hasPrefix("127.")
    }

    private var hostForURL: String {
        if host.contains(":") && !host.hasPrefix("[") { return "[\(host)]" }
        return host
    }

    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        let hostPart = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(hostPart):\(port)"
    }
}
