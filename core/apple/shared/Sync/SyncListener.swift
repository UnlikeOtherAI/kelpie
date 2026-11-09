import Foundation
import Network

/// The three sync endpoints. The listener serves nothing else.
enum SyncRoute: String, CaseIterable {
    case hello = "/v1/sync/hello"
    case auth = "/v1/sync/auth"
    case exchange = "/v1/sync/exchange"

    var bodyLimit: Int { self == .exchange ? SyncListener.exchangeBodyLimit : SyncListener.handshakeBodyLimit }
}

enum SyncAdmission {
    case accept
    case reject(SyncHTTPResponse)
}

/// The sync-only HTTP listener on an ephemeral port, separate from automation.
///
/// A connection is dropped unless its peer passes the address rule. Each request must be
/// a `POST` with `Content-Type: application/json` and exactly one decimal
/// `Content-Length`; `Origin` and `Transfer-Encoding` are refused. Limits are checked on
/// the request head, before any of the body is read: 16 KiB for `hello`/`auth` with a 5 s
/// read deadline, 4 MiB for `exchange`, which is admitted only with a live
/// `X-Kelpie-Sync-Session` header. Rate limits and sessions belong to the `admit` closure.
final class SyncListener: @unchecked Sendable {
    typealias Admit = @Sendable (SyncRoute, SyncHTTPHead, String) async -> SyncAdmission
    typealias Handle = @Sendable (SyncRoute, SyncHTTPHead, Data, String) async -> SyncHTTPResponse

    static let headerLimit = 16 * 1024
    static let handshakeBodyLimit = 16 * 1024
    static let exchangeBodyLimit = 4 * 1024 * 1024
    static let readDeadline: TimeInterval = 5
    static let exchangeReadDeadline: TimeInterval = 30
    static let maxConnections = 32
    static let serviceType = "_kelpie-sync._tcp"

    private let rule: SyncAddressRule
    private let admit: Admit
    private let handle: Handle
    private let lock = NSLock()
    private var listener: NWListener?
    private var service: NWListener.Service?
    private var stateChanged: (@Sendable (UInt16?) -> Void)?
    private var connections = 0
    private var stopped = false

    init(rule: SyncAddressRule, admit: @escaping Admit, handle: @escaping Handle) {
        self.rule = rule
        self.admit = admit
        self.handle = handle
    }

    /// Starts listening. `stateChanged` receives the bound port when ready and nil when the
    /// listener fails; a failed listener is recreated after 5 s until stopped.
    func start(service: NWListener.Service?, stateChanged: @escaping @Sendable (UInt16?) -> Void) {
        lock.lock()
        self.service = service
        self.stateChanged = stateChanged
        lock.unlock()
        open()
    }

    var port: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return listener?.port?.rawValue
    }

    func setService(_ service: NWListener.Service?) {
        lock.lock()
        self.service = service
        let current = listener
        lock.unlock()
        current?.service = service
    }

    func stop() {
        lock.lock()
        stopped = true
        let current = listener
        listener = nil
        stateChanged = nil
        lock.unlock()
        current?.cancel()
    }

    /// The checks that need no session state. Returns the route or the refusal.
    static func check(_ head: SyncHTTPHead) -> Result<SyncRoute, SyncRefusal> {
        guard head.method == "POST" else { return .failure(SyncRefusal(.error(405, "METHOD_NOT_ALLOWED"))) }
        guard let route = SyncRoute(rawValue: head.path) else { return .failure(SyncRefusal(.error(404, "NOT_FOUND"))) }
        if head.headers["origin"] != nil { return .failure(SyncRefusal(.error(403, "ORIGIN_REJECTED"))) }
        if head.headers["transfer-encoding"] != nil { return .failure(SyncRefusal(.error(400, "TRANSFER_ENCODING"))) }
        switch head.headers["content-length"]?.count ?? 0 {
        case 0: return .failure(SyncRefusal(.error(411, "LENGTH_REQUIRED")))
        case 1: break
        default: return .failure(SyncRefusal(.error(400, "DUPLICATE_CONTENT_LENGTH")))
        }
        guard let length = head.contentLength else { return .failure(SyncRefusal(.error(400, "INVALID_CONTENT_LENGTH"))) }
        let type = head.value("content-type")?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard type == "application/json" else { return .failure(SyncRefusal(.error(415, "UNSUPPORTED_MEDIA_TYPE"))) }
        guard length <= route.bodyLimit else { return .failure(SyncRefusal(.error(413, "PAYLOAD_TOO_LARGE"))) }
        return .success(route)
    }

    static func sourceAddress(_ endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "unknown" }
        switch host {
        case .ipv4(let address): return "\(address)"
        case .ipv6(let address): return "\(address)".split(separator: "%").first.map(String.init) ?? "\(address)"
        default: return "unknown"
        }
    }

    private func open() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        let parameters = NWParameters.tcp
        parameters.prohibitedInterfaceTypes = [.cellular]
        guard let created = try? NWListener(using: parameters, on: .any) else {
            scheduleReopen()
            return
        }
        created.service = service
        created.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        created.stateUpdateHandler = { [weak self, weak created] state in
            guard let self, let created else { return }
            switch state {
            case .ready: self.report(created.port?.rawValue, from: created)
            case .failed:
                self.report(nil, from: created)
                created.cancel()
                self.lock.lock()
                if self.listener === created { self.scheduleReopen() }
                self.lock.unlock()
            default: break
            }
        }
        listener = created
        created.start(queue: SyncNetwork.queue)
    }

    /// Caller holds the lock.
    private func scheduleReopen() {
        guard !stopped else { return }
        listener = nil
        SyncNetwork.queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.open() }
    }

    private func report(_ port: UInt16?, from source: NWListener) {
        lock.lock()
        let current = listener === source ? stateChanged : nil
        lock.unlock()
        current?(port)
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        let admitted = !stopped && connections < Self.maxConnections && rule.allows(connection.endpoint)
        if admitted { connections += 1 }
        lock.unlock()
        guard admitted else {
            connection.cancel()
            return
        }
        let source = Self.sourceAddress(connection.endpoint)
        SyncServerConnection(connection: connection, source: source, admit: admit, handle: handle) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.connections -= 1
            self.lock.unlock()
        }.start()
    }
}

/// A refused request, carried through `Result`.
struct SyncRefusal: Error {
    let response: SyncHTTPResponse

    init(_ response: SyncHTTPResponse) { self.response = response }
}

/// Reads one request, enforcing the head limit, body limit and read deadline, then
/// answers it and closes. The deadline stops applying once the request is dispatched;
/// a long-poll handler bounds its own wait.
private final class SyncServerConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let source: String
    private let admit: SyncListener.Admit
    private let handle: SyncListener.Handle
    private let closed: @Sendable () -> Void
    private var buffer = Data()
    private var phase = 0
    private var answered = false
    private var finished = false

    init(
        connection: NWConnection,
        source: String,
        admit: @escaping SyncListener.Admit,
        handle: @escaping SyncListener.Handle,
        closed: @escaping @Sendable () -> Void
    ) {
        self.connection = connection
        self.source = source
        self.admit = admit
        self.handle = handle
        self.closed = closed
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .failed, .cancelled: finish()
            default: break
            }
        }
        connection.start(queue: SyncNetwork.queue)
        armDeadline(SyncListener.readDeadline)
        readHead()
    }

    private func armDeadline(_ seconds: TimeInterval) {
        phase += 1
        let armed = phase
        SyncNetwork.queue.asyncAfter(deadline: .now() + seconds) { [self] in
            if phase == armed { respond(.error(408, "REQUEST_TIMEOUT")) }
        }
    }

    private func readHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] content, _, isComplete, error in
            if let content { buffer.append(content) }
            guard let end = buffer.range(of: SyncHTTPHead.terminator) else {
                if buffer.count > SyncListener.headerLimit {
                    respond(.error(431, "HEADERS_TOO_LARGE"))
                } else if isComplete || error != nil {
                    finish()
                } else {
                    readHead()
                }
                return
            }
            guard end.lowerBound - buffer.startIndex <= SyncListener.headerLimit,
                  let head = SyncHTTPHead.parse(buffer[buffer.startIndex..<end.lowerBound]) else {
                respond(.error(400, "BAD_REQUEST"))
                return
            }
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            admitRequest(head)
        }
    }

    private func admitRequest(_ head: SyncHTTPHead) {
        let route: SyncRoute
        switch SyncListener.check(head) {
        case .failure(let refusal):
            respond(refusal.response)
            return
        case .success(let checked):
            route = checked
        }
        Task { [self] in
            let decision = await admit(route, head, source)
            SyncNetwork.queue.async { [self] in
                guard case .accept = decision else {
                    if case .reject(let response) = decision { respond(response) }
                    return
                }
                if route == .exchange { armDeadline(SyncListener.exchangeReadDeadline) }
                readBody(route: route, head: head, length: head.contentLength ?? 0)
            }
        }
    }

    private func readBody(route: SyncRoute, head: SyncHTTPHead, length: Int) {
        if buffer.count > length {
            respond(.error(400, "BAD_REQUEST"))
            return
        }
        if buffer.count == length {
            phase += 1  // dispatched: the read deadline no longer applies
            let body = buffer
            Task { [self] in
                let response = await handle(route, head, body, source)
                SyncNetwork.queue.async { [self] in respond(response) }
            }
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(65_536, length - buffer.count)) { [self] content, _, isComplete, error in
            if let content { buffer.append(content) }
            if buffer.count < length, isComplete || error != nil {
                finish()
                return
            }
            readBody(route: route, head: head, length: length)
        }
    }

    private func respond(_ response: SyncHTTPResponse) {
        guard !answered else { return }
        answered = true
        phase += 1
        connection.send(content: response.render(), completion: .contentProcessed { [self] _ in connection.cancel() })
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        phase += 1
        answered = true
        closed()
    }
}
