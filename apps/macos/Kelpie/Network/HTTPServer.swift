import Foundation
import Network

/// Errors thrown by HTTPServer for unrecoverable startup conditions.
enum HTTPServerError: Error, CustomStringConvertible {
    case invalidPort(UInt16)

    var description: String {
        switch self {
        case .invalidPort(let port):
            return "Invalid HTTP server port: \(port)"
        }
    }
}

/// Embedded HTTP server for receiving CLI commands.
/// Uses raw NWListener since we want zero external dependencies for the server.
final class HTTPServer: @unchecked Sendable {
    /// Maximum bytes accepted for HTTP request headers before parsing must complete.
    /// 16 KiB matches Nginx/Apache defaults and keeps slow-loris pinning bounded.
    static let maxHeaderBytes = 16 * 1024
    /// Maximum request body size accepted by the server (32 MiB).
    /// Larger bodies receive `413 Payload Too Large` and the connection is closed.
    static let maxBodyBytes = 32 * 1024 * 1024
    /// Maximum lifetime of a single HTTP connection from first byte to dispatch.
    /// Prevents slow-loris clients from pinning sockets indefinitely.
    static let requestTimeoutSeconds: Double = 30

    let port: UInt16
    let router: Router
    private let lock = NSLock()
    private var listener: NWListener?
    private var bonjourService: NWListener.Service?
    var onBonjourStateChange: ((Bool) -> Void)? {
        get { lock.withLock { _onBonjourStateChange } }
        set { lock.withLock { _onBonjourStateChange = newValue } }
    }
    var onStateChange: ((Bool) -> Void)? {
        get { lock.withLock { _onStateChange } }
        set { lock.withLock { _onStateChange = newValue } }
    }
    /// Fired exactly when the underlying NWListener transitions to `.ready`.
    /// Used by ServerState to publish mDNS only after the socket is accepting
    /// connections — otherwise Bonjour announces a port that returns
    /// ECONNREFUSED for the brief window before `.ready` arrives.
    var onReady: (() -> Void)? {
        get { lock.withLock { _onReady } }
        set { lock.withLock { _onReady = newValue } }
    }
    private var _onBonjourStateChange: ((Bool) -> Void)?
    private var _onStateChange: ((Bool) -> Void)?
    private var _onReady: (() -> Void)?

    init(port: UInt16 = 8420, router: Router) throws {
        // `UInt16` already constrains the upper bound (<= 65535); port 0 is
        // the wildcard / "any port" sentinel and is never something we want
        // to advertise via mDNS, so reject it explicitly rather than crashing
        // inside `NWEndpoint.Port(rawValue:)` later.
        guard port > 0 else { throw HTTPServerError.invalidPort(port) }
        self.port = port
        self.router = router
    }

    func configureBonjourService(
        name: String,
        type: String,
        txtRecord: NWTXTRecord
    ) {
        lock.lock()
        defer { lock.unlock() }
        bonjourService = NWListener.Service(name: name, type: type, txtRecord: txtRecord)
        listener?.service = bonjourService
    }

    func start() {
        // `port` was validated at construction (>0 and <= 65535 by type), so
        // `NWEndpoint.Port(rawValue:)` cannot fail — no force-unwrap needed.
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            print("[HTTPServer] Invalid port \(port) — refusing to start")
            onBonjourStateChange?(false)
            onStateChange?(false)
            return
        }

        let newListener: NWListener
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            newListener = try NWListener(using: params, on: endpointPort)
        } catch {
            print("[HTTPServer] Failed to create listener: \(error)")
            onBonjourStateChange?(false)
            return
        }

        lock.lock()
        listener = newListener
        let svc = bonjourService
        lock.unlock()

        newListener.service = svc
        newListener.serviceRegistrationUpdateHandler = { [weak self] change in
            guard let self else { return }
            switch change {
            case .add(let endpoint):
                print("[mDNS] Advertising: \(endpoint)")
                self.onBonjourStateChange?(true)
            case .remove(let endpoint):
                print("[mDNS] Removed: \(endpoint)")
                self.onBonjourStateChange?(false)
            @unknown default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("[HTTPServer] Listening on port \(self.port)")
                self.onStateChange?(true)
                self.onReady?()
            case .failed(let error):
                print("[HTTPServer] Listener failed: \(error)")
                self.onBonjourStateChange?(false)
                self.onStateChange?(false)
            case .cancelled:
                self.onBonjourStateChange?(false)
                self.onStateChange?(false)
            default:
                break
            }
        }
        newListener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        lock.lock()
        let current = listener
        listener = nil
        bonjourService = nil
        lock.unlock()
        // Clear the Bonjour service first so the mDNS withdrawal goes out
        // before the listener is cancelled — clients should stop seeing the
        // advertised endpoint slightly before the socket disappears.
        current?.service = nil
        current?.cancel()
        onBonjourStateChange?(false)
        onStateChange?(false)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        let deadline = Date().addingTimeInterval(Self.requestTimeoutSeconds)
        receiveData(connection: connection, buffer: Data(), deadline: deadline)
    }

    /// Recursively drains `connection` into `buffer`, enforcing header-byte,
    /// body-byte, and overall-deadline limits. Each invocation re-checks the
    /// deadline before requesting more data so slow-loris clients are bounded.
    private func receiveData(connection: NWConnection, buffer: Data, deadline: Date) {
        if Date() >= deadline {
            send408AndClose(connection: connection)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let content { accumulated.append(content) }

            if isComplete || error != nil {
                Task { await self.processRequest(connection: connection, data: accumulated) }
                return
            }

            self.continueReceive(connection: connection, accumulated: accumulated, deadline: deadline)
        }
    }

    private func continueReceive(connection: NWConnection, accumulated: Data, deadline: Date) {
        let headerSeparator = accumulated.range(of: Data("\r\n\r\n".utf8))

        // Enforce header byte cap before headers complete. Closing early
        // bounds slow-loris connections that drip a few bytes at a time.
        if headerSeparator == nil, accumulated.count > Self.maxHeaderBytes {
            send413AndClose(connection: connection, message: "Request header exceeds \(Self.maxHeaderBytes) bytes")
            return
        }

        guard let headerEnd = headerSeparator else {
            receiveData(connection: connection, buffer: accumulated, deadline: deadline)
            return
        }

        let headerByteCount = accumulated.distance(from: accumulated.startIndex, to: headerEnd.lowerBound)
        // Reject oversized headers even when they arrive in a single chunk —
        // the headers-complete branch above only catches drip-feed clients.
        if headerByteCount > Self.maxHeaderBytes {
            send413AndClose(connection: connection, message: "Request header exceeds \(Self.maxHeaderBytes) bytes")
            return
        }

        let headerString = String(data: accumulated[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        let bodyStart = headerEnd.upperBound
        let bodyReceived = accumulated.distance(from: bodyStart, to: accumulated.endIndex)

        switch parseContentLength(headerString) {
        case .valid(let contentLength):
            if contentLength > Self.maxBodyBytes {
                send413AndClose(
                    connection: connection,
                    message: "Content-Length \(contentLength) exceeds limit of \(Self.maxBodyBytes) bytes"
                )
                return
            }
            if bodyReceived >= contentLength {
                Task { await self.processRequest(connection: connection, data: accumulated) }
            } else {
                receiveData(connection: connection, buffer: accumulated, deadline: deadline)
            }
        case .missing:
            // Reject POSTs without Content-Length; GETs never have a body.
            let requestLine = headerString.components(separatedBy: "\r\n").first ?? ""
            if requestLine.hasPrefix("POST ") {
                send411AndClose(connection: connection)
            } else {
                Task { await self.processRequest(connection: connection, data: accumulated) }
            }
        case .malformed:
            send400AndClose(connection: connection, message: "Malformed Content-Length")
        }
    }

    private enum ContentLengthParseResult {
        case valid(Int)
        case missing
        case malformed
    }

    /// Strictly parses the `Content-Length` header. Rejects negatives,
    /// non-integer values, and trailing garbage. RFC 7230 §3.3.2 requires
    /// a non-negative decimal — `Int("-1")` parses successfully and used to
    /// pass through as a body-size of -1, making `bodyReceived >= -1` always
    /// true and short-circuiting the read loop.
    private func parseContentLength(_ headers: String) -> ContentLengthParseResult {
        for line in headers.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let parsed = Int(value) else {
                return .malformed
            }
            return .valid(parsed)
        }
        return .missing
    }

    private func send408AndClose(connection: NWConnection) {
        let body = Data(#"{"error":"Request timeout"}"#.utf8)
        let response = buildHTTPResponse(statusCode: 408, body: body, contentType: "application/json")
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func send411AndClose(connection: NWConnection) {
        let body = Data(#"{"error":"Content-Length required"}"#.utf8)
        let response = buildHTTPResponse(statusCode: 411, body: body, contentType: "application/json")
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func send413AndClose(connection: NWConnection, message: String) {
        let payload: [String: Any] = ["error": message]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data(#"{"error":"Payload too large"}"#.utf8)
        let response = buildHTTPResponse(statusCode: 413, body: body, contentType: "application/json")
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func send400AndClose(connection: NWConnection, message: String) {
        let payload: [String: Any] = ["error": message]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data(#"{"error":"Bad request"}"#.utf8)
        let response = buildHTTPResponse(statusCode: 400, body: body, contentType: "application/json")
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func processRequest(connection: NWConnection, data: Data) async {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let (requestLine, body) = parseHTTPRequest(raw)
        let parts = requestLine.split(separator: " ")
        let httpMethod = parts.first.map(String.init) ?? "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        var statusCode = 200
        var responseData = Data()
        var contentType = "application/json"

        if httpMethod == "POST", path.hasPrefix("/v1/") {
            let method = String(path.dropFirst("/v1/".count))
            guard let jsonBody = parseJSON(body) else {
                statusCode = 400
                responseData = (try? JSONSerialization.data(
                    withJSONObject: errorResponse(code: "INVALID_JSON", message: "Request body is not valid JSON")
                )) ?? Data("{}".utf8)
                let response = buildHTTPResponse(statusCode: statusCode, body: responseData, contentType: contentType)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            let (code, result) = await router.handle(method: method, body: jsonBody)
            statusCode = code
            responseData = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
        } else if httpMethod == "GET", path == "/debug/coordinate-calibration" {
            if let page = coordinateCalibrationPage() {
                responseData = page
                contentType = "text/html; charset=utf-8"
            } else {
                statusCode = 500
                responseData = Data(#"{"error":"Coordinate calibration page missing from bundle"}"#.utf8)
            }
        } else if path == "/health" {
            responseData = Data(#"{"status":"ok"}"#.utf8)
        } else {
            statusCode = 404
            responseData = Data(#"{"error":"Not found"}"#.utf8)
        }

        let response = buildHTTPResponse(statusCode: statusCode, body: responseData, contentType: contentType)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func parseHTTPRequest(_ raw: String) -> (requestLine: String, body: String) {
        guard let headerEnd = raw.range(of: "\r\n\r\n") else {
            return (raw.components(separatedBy: "\r\n").first ?? "", "")
        }
        let requestLine = raw[..<headerEnd.lowerBound].components(separatedBy: "\r\n").first ?? ""
        let body = String(raw[headerEnd.upperBound...])
        return (requestLine, body)
    }

    private func parseJSON(_ body: String) -> [String: Any]? {
        guard !body.isEmpty else { return [:] }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func coordinateCalibrationPage() -> Data? {
        if let url = Bundle.main.url(forResource: "coordinate-calibration", withExtension: "html") {
            return try? Data(contentsOf: url)
        }
        if let url = Bundle.main.url(
            forResource: "coordinate-calibration",
            withExtension: "html",
            subdirectory: "Resources"
        ) {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    private func buildHTTPResponse(statusCode: Int, body: Data, contentType: String) -> Data {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 408: statusText = "Request Timeout"
        case 411: statusText = "Length Required"
        case 413: statusText = "Payload Too Large"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        let header = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        return response
    }
}
