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
///
/// All `/v1/*` routes (except the unauth allowlist enforced by `AuthMiddleware`)
/// require a bearer token issued by the pairing flow. CORS headers are not
/// emitted — CLI fetch is not a browser.
final class HTTPServer: @unchecked Sendable {
    /// Maximum bytes accepted for HTTP request headers before parsing must complete.
    /// 64 KiB caps slow-loris pinning while leaving room for cookies and auth headers.
    /// Mirrors iOS and Android.
    static let maxHeaderBytes = 64 * 1024
    /// Maximum request body size accepted by the server (50 MiB).
    /// Larger bodies receive `413 Payload Too Large` and the connection is closed.
    /// Mirrors iOS and Android.
    static let maxBodyBytes = 50 * 1024 * 1024
    /// Maximum lifetime of a single HTTP connection from first byte to dispatch.
    /// Prevents slow-loris clients from pinning sockets indefinitely.
    static let requestTimeoutSeconds: Double = 30

    let port: UInt16
    let router: Router
    let pairingStore: PairingStore
    let deviceInfo: DeviceInfo
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
    /// Invoked on the main actor after a new pending pair request is recorded.
    var onPendingPairChanged: (@MainActor () -> Void)? {
        get { lock.withLock { _onPendingPairChanged } }
        set { lock.withLock { _onPendingPairChanged = newValue } }
    }
    private var _onBonjourStateChange: ((Bool) -> Void)?
    private var _onStateChange: ((Bool) -> Void)?
    private var _onReady: (() -> Void)?
    private var _onPendingPairChanged: (@MainActor () -> Void)?

    init(port: UInt16 = 8420, router: Router, pairingStore: PairingStore, deviceInfo: DeviceInfo) throws {
        // `UInt16` already constrains the upper bound (<= 65535); port 0 is
        // the wildcard / "any port" sentinel and is never something we want
        // to advertise via mDNS, so reject it explicitly rather than crashing
        // inside `NWEndpoint.Port(rawValue:)` later.
        guard port > 0 else { throw HTTPServerError.invalidPort(port) }
        self.port = port
        self.router = router
        self.pairingStore = pairingStore
        self.deviceInfo = deviceInfo
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
            send431HeaderAndClose(connection: connection)
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
            send431HeaderAndClose(connection: connection)
            return
        }

        let headerString = String(data: accumulated[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        let bodyStart = headerEnd.upperBound
        let bodyReceived = accumulated.distance(from: bodyStart, to: accumulated.endIndex)

        switch parseContentLength(headerString) {
        case .valid(let contentLength):
            if contentLength > Self.maxBodyBytes {
                send413BodyAndClose(connection: connection)
                return
            }
            // Guard against clients that under-declare Content-Length and then
            // stream more bytes — drop the connection if total exceeds either
            // the declared length or the global cap.
            if bodyReceived > contentLength || bodyReceived > Self.maxBodyBytes {
                send413BodyAndClose(connection: connection)
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
        sendErrorAndClose(connection: connection, status: 408, code: "REQUEST_TIMEOUT", message: "Request timed out before completion")
    }

    private func send411AndClose(connection: NWConnection) {
        sendErrorAndClose(connection: connection, status: 411, code: "LENGTH_REQUIRED", message: "Content-Length header is required")
    }

    private func send413BodyAndClose(connection: NWConnection) {
        let mb = Self.maxBodyBytes / (1024 * 1024)
        sendErrorAndClose(connection: connection, status: 413, code: "PAYLOAD_TOO_LARGE", message: "Request body exceeds \(mb) MB limit")
    }

    private func send431HeaderAndClose(connection: NWConnection) {
        let kb = Self.maxHeaderBytes / 1024
        sendErrorAndClose(connection: connection, status: 431, code: "REQUEST_HEADER_FIELDS_TOO_LARGE", message: "Request headers exceed \(kb) KB limit")
    }

    private func send400AndClose(connection: NWConnection, message: String) {
        sendErrorAndClose(connection: connection, status: 400, code: "BAD_REQUEST", message: message)
    }

    private func sendErrorAndClose(connection: NWConnection, status: Int, code: String, message: String) {
        let response = PairingHTTPResponse.error(status: status, code: code, message: message)
        connection.send(content: response.render(), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func processRequest(connection: NWConnection, data: Data) async {
        let sourceAddress = HTTPRequestParser.formatSourceAddress(connection.endpoint)
        guard let parsed = HTTPRequestParser.parse(data: data, sourceAddress: sourceAddress) else {
            await send(connection: connection, response: PairingHTTPResponse.malformed())
            return
        }

        let middleware = AuthMiddleware(store: pairingStore)
        let decision = middleware.evaluate(parsed)
        switch decision {
        case let .reject(status, code, message):
            await send(
                connection: connection,
                response: PairingHTTPResponse.error(status: status, code: code, message: message)
            )
        case .unauthenticated:
            await routeUnauthenticated(parsed: parsed, connection: connection)
        case let .authenticated(clientId):
            await routeAuthenticated(parsed: parsed, clientId: clientId, connection: connection)
        }
    }

    private func routeUnauthenticated(parsed: ParsedHTTPRequest, connection: NWConnection) async {
        let pairEndpoints = PairEndpoints(store: pairingStore, onPendingChanged: onPendingPairChanged)
        switch (parsed.method, parsed.path) {
        case ("POST", "/v1/pair"):
            let result = pairEndpoints.handlePairPost(body: parsed.body, sourceAddress: parsed.sourceAddress)
            await send(
                connection: connection,
                response: PairingHTTPResponse.json(status: result.status, json: result.json, noStore: true)
            )
        case ("GET", "/v1/pair/status"):
            let result = pairEndpoints.handlePairStatus(query: parsed.query, sourceAddress: parsed.sourceAddress)
            await send(
                connection: connection,
                response: PairingHTTPResponse.json(status: result.status, json: result.json, noStore: true)
            )
        case ("GET", "/v1/get-device-info"):
            let result = pairEndpoints.handleGetDeviceInfo(
                name: deviceInfo.name,
                platform: deviceInfo.platform,
                version: deviceInfo.version
            )
            await send(
                connection: connection,
                response: PairingHTTPResponse.json(status: result.status, json: result.json)
            )
        case ("GET", "/health"):
            await send(connection: connection, response: PairingHTTPResponse.healthOk())
        default:
            await send(
                connection: connection,
                response: PairingHTTPResponse.error(status: 404, code: "NOT_FOUND", message: "Not found")
            )
        }
    }

    private func routeAuthenticated(parsed: ParsedHTTPRequest, clientId: String, connection: NWConnection) async {
        let pairEndpoints = PairEndpoints(store: pairingStore, onPendingChanged: nil)
        switch (parsed.method, parsed.path) {
        case ("DELETE", "/v1/pair"):
            let result = pairEndpoints.handlePairDelete(authenticatedClientId: clientId)
            await send(
                connection: connection,
                response: PairingHTTPResponse.json(status: result.status, json: result.json, noStore: true)
            )
        case ("GET", "/debug/coordinate-calibration"):
            if let page = coordinateCalibrationPage() {
                await send(
                    connection: connection,
                    response: PairingHTTPResponse(
                        status: 200, body: page, contentType: "text/html; charset=utf-8", noStore: false
                    )
                )
            } else {
                await send(
                    connection: connection,
                    response: PairingHTTPResponse.error(
                        status: 500, code: "WEBVIEW_ERROR", message: "Coordinate calibration page missing"
                    )
                )
            }
        default:
            if parsed.method == "POST", parsed.path.hasPrefix("/v1/") {
                await handlePOSTv1(parsed: parsed, connection: connection)
            } else {
                await send(
                    connection: connection,
                    response: PairingHTTPResponse.error(status: 404, code: "NOT_FOUND", message: "Not found")
                )
            }
        }
    }

    private func handlePOSTv1(parsed: ParsedHTTPRequest, connection: NWConnection) async {
        let method = String(parsed.path.dropFirst("/v1/".count))
        let bodyString = String(data: parsed.body, encoding: .utf8) ?? ""
        guard let jsonBody = parseJSON(bodyString) else {
            await send(
                connection: connection,
                response: PairingHTTPResponse.error(
                    status: 400, code: "INVALID_JSON", message: "Request body is not valid JSON"
                )
            )
            return
        }
        let (code, result) = await router.handle(method: method, body: jsonBody)
        await send(connection: connection, response: PairingHTTPResponse.json(status: code, json: result))
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

    private func send(connection: NWConnection, response: PairingHTTPResponse) async {
        connection.send(content: response.render(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
