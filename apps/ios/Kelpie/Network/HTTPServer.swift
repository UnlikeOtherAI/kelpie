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
///
/// Uses raw NWListener since we want zero external dependencies for the server.
///
/// The same `NWListener` also carries the Bonjour/mDNS advertisement when one
/// is attached via `attachService(_:)`. This keeps the published port and the
/// listening port in lockstep — Network.framework publishes whatever port the
/// listener is bound to, so advertising via a second standalone listener would
/// announce an ephemeral port that no one is serving on.
///
/// All `/v1/*` routes (except the unauth allowlist in `AuthMiddleware`) require
/// a bearer token issued by the pairing flow.
final class HTTPServer: @unchecked Sendable {
    /// Maximum bytes accepted for HTTP request headers before parsing must complete.
    /// 64 KiB caps slow-loris pinning while leaving room for cookies and auth headers.
    /// Mirrors macOS and Android.
    static let maxHeaderBytes = 64 * 1024
    /// Maximum request body size accepted by the server (50 MiB).
    /// Larger bodies receive `413 Payload Too Large` and the connection is closed.
    /// Mirrors macOS and Android.
    static let maxBodyBytes = 50 * 1024 * 1024
    /// Maximum lifetime of a single HTTP connection from first byte to dispatch.
    /// Prevents slow-loris clients from pinning sockets indefinitely.
    static let requestTimeoutSeconds: Double = 30

    let port: UInt16
    let router: Router
    let pairingStore: PairingStore
    let deviceInfo: DeviceInfo
    private var listener: NWListener?
    private var pendingService: NWListener.Service?
    var serviceRegistrationUpdateHandler: ((NWListener.ServiceRegistrationChange) -> Void)?
    /// Invoked on the main actor after a new pending pair request is recorded.
    var onPendingPairChanged: (@MainActor () -> Void)?

    init(port: UInt16 = 8420, router: Router, pairingStore: PairingStore, deviceInfo: DeviceInfo) throws {
        guard port > 0 else { throw HTTPServerError.invalidPort(port) }
        self.port = port
        self.router = router
        self.pairingStore = pairingStore
        self.deviceInfo = deviceInfo
    }

    func start() {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            print("[HTTPServer] Invalid port \(port) — refusing to start")
            return
        }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: endpointPort)
        } catch {
            print("[HTTPServer] Failed to create listener: \(error)")
            return
        }

        if let service = pendingService {
            listener?.service = service
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("[HTTPServer] Listening on port \(self.port)")
            case .failed(let error):
                print("[HTTPServer] Listener failed: \(error)")
            default:
                break
            }
        }
        listener?.serviceRegistrationUpdateHandler = { [weak self] change in
            self?.serviceRegistrationUpdateHandler?(change)
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Attach a Bonjour service to the listener. If the listener is already
    /// running the service starts publishing immediately; otherwise it is held
    /// until `start()` is called. Passing `nil` clears the service.
    func attachService(_ service: NWListener.Service?) {
        pendingService = service
        listener?.service = service
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
    /// a non-negative decimal — a permissive parser previously let `-1`
    /// short-circuit the read loop.
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
        let bytes = response.render()
        connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
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
            await send(connection: connection, response: PairingHTTPResponse.error(status: status, code: code, message: message))
            return
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
            await send(connection: connection, response: PairingHTTPResponse.json(status: result.status, json: result.json))
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
                    response: PairingHTTPResponse(status: 200, body: page, contentType: "text/html; charset=utf-8", noStore: false)
                )
            } else {
                await send(
                    connection: connection,
                    response: PairingHTTPResponse.error(status: 500, code: "WEBVIEW_ERROR", message: "Coordinate calibration page missing")
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
                response: PairingHTTPResponse.error(status: 400, code: "INVALID_JSON", message: "Request body is not valid JSON")
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
        guard let url = Bundle.main.url(forResource: "coordinate-calibration", withExtension: "html") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func send(connection: NWConnection, response: PairingHTTPResponse) async {
        let bytes = response.render()
        connection.send(content: bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
