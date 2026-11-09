import CryptoKit
import Foundation
import Network
import XCTest
@testable import KelpieBrowser

/// A UOA stand-in: a ticket is a deterministic function of the issuing subject, the
/// challenge and the client id, and validation recomputes it with the validator's own
/// subject, so a ticket only validates for the same account, transcript and role.
@MainActor
final class FakeSyncAccount: SyncAccount {
    var subject: String?
    /// The subject tickets are issued for; differs from `subject` for an impostor.
    var ticketSubject: String?
    var generation = UUID().uuidString
    private(set) var issued = 0
    private(set) var validated = 0
    private var handler: (@MainActor () -> Void)?

    init(subject: String?) {
        self.subject = subject
    }

    var fence: SyncFence? { subject.map { SyncFence(subject: $0, generation: generation) } }

    func observe(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }

    func signIn(_ subject: String) {
        self.subject = subject
        generation = UUID().uuidString
        handler?()
    }

    func signOut() {
        subject = nil
        generation = UUID().uuidString
        handler?()
    }

    func issueTicket(challenge: String, clientId: String) async throws -> String {
        issued += 1
        guard let owner = ticketSubject ?? subject else { throw URLError(.userAuthenticationRequired) }
        return Self.ticket(owner, challenge, clientId)
    }

    func validateTicket(_ ticket: String, challenge: String, clientId: String) async throws -> Bool {
        validated += 1
        guard let subject else { throw URLError(.userAuthenticationRequired) }
        return ticket == Self.ticket(subject, challenge, clientId)
    }

    static func ticket(_ subject: String, _ challenge: String, _ clientId: String) -> String {
        let digest = SHA256.hash(data: Data("\(subject)\u{0}\(challenge)\u{0}\(clientId)".utf8))
        return "t." + digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// An in-memory cookie engine that honours the read-back contract.
@MainActor
final class MemoryCookieSource: SyncCookieSource {
    private(set) var cookies: [String: [String: Any]] = [:]
    private var handler: (@MainActor () -> Void)?

    static func key(_ domain: String, _ path: String, _ name: String) -> String { "\(domain.lowercased())\u{0}\(path)\u{0}\(name)" }

    func snapshot() async throws -> SyncCookieSnapshot {
        SyncCookieSnapshot(cookiesJSON: SyncJSON.string(Array(cookies.values)), coverageJSON: #"{"all":true}"#)
    }

    func apply(_ op: SyncCookieOp, isCurrent: @escaping @MainActor () -> Bool) async -> SyncCookieOpResult {
        guard let cookie = SyncJSON.object(op.cookieJSON), let domain = cookie["domain"] as? String,
              let name = cookie["name"] as? String else { return SyncCookieOpResult(id: op.id, ok: false, readbackJSON: "[]") }
        let key = Self.key(domain, cookie["path"] as? String ?? "/", name)
        if op.isDelete { cookies.removeValue(forKey: key) } else { cookies[key] = cookie }
        let host = SyncCookieWire.host(of: domain)
        let readback = cookies.values.filter { ($0["name"] as? String) == name && SyncCookieWire.host(of: $0["domain"] as? String ?? "") == host }
        return SyncCookieOpResult(id: op.id, ok: true, readbackJSON: SyncJSON.string(readback))
    }

    func setChangeHandler(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }

    /// A site sets a cookie: write it and signal the change.
    func set(_ domain: String, _ name: String, _ value: String, expires: Int64? = Int64(Date().timeIntervalSince1970) + 86_400) {
        cookies[Self.key(domain, "/", name)] = [
            "domain": domain, "path": "/", "name": name, "value": value,
            "expires": expires.map { NSNumber(value: $0) } ?? NSNull(), "secure": true, "httpOnly": true, "sameSite": "Lax"
        ]
        handler?()
    }

    func remove(_ domain: String, _ name: String) {
        cookies.removeValue(forKey: Self.key(domain, "/", name))
        handler?()
    }

    func value(_ domain: String, _ name: String) -> String? { cookies[Self.key(domain, "/", name)]?["value"] as? String }

    /// What an app restart does to the engine: session cookies are gone.
    func dropSessionCookies() { cookies = cookies.filter { !($0.value["expires"] is NSNull) } }
}

/// Discovery the test controls: adverts point at loopback listeners.
@MainActor
final class StaticDiscovery: SyncDiscovery {
    let context: SyncDiscoveryContext
    private var adverts: [SyncAdvert] = []
    private var onChange: (@MainActor ([SyncAdvert]) -> Void)?

    init(context: SyncDiscoveryContext) {
        self.context = context
    }

    func start(onChange: @escaping @MainActor ([SyncAdvert]) -> Void) {
        self.onChange = onChange
        refresh()
    }

    func stop() { onChange = nil }

    func publish(_ adverts: [SyncAdvert]) {
        self.adverts = adverts
        refresh()
    }

    func refresh() {
        let accepted = context.acceptedHints()
        onChange?(adverts.filter { $0.replica != context.ownReplica && accepted.contains($0.hint) })
    }

    func resolve(_ advert: SyncAdvert) async -> NWEndpoint? { advert.endpoint }
}

extension SyncTiming {
    static let fast = SyncTiming(
        warmupMinimum: 0.3, warmupMaximum: 1.5, initiatorFallback: 0.5, scanQuiet: 0.05,
        sessionMillis: 600_000, pendingMillis: 60_000, pullWaitMillis: 3_000, warmingRetry: 0.1,
        backoffMinimum: 0.2, backoffMaximum: 1
    )
}

/// One simulated Kelpie: an account, an engine, a store file and a "process" whose first
/// store open is `launch:true`.
@MainActor
final class SyncTestDevice {
    let name: String
    let account: FakeSyncAccount
    let source = MemoryCookieSource()
    let storeURL: URL
    var timing = SyncTiming.fast
    private(set) var service: CookieSyncService?
    private(set) var discovery: StaticDiscovery?
    private var launched = false

    init(_ name: String, subject: String?, directory: URL) {
        self.name = name
        account = FakeSyncAccount(subject: subject)
        storeURL = directory.appendingPathComponent(name).appendingPathComponent("cookie-sync.json")
    }

    func boot() {
        var environment = SyncEnvironment(platform: "ios", deviceName: name, storeURL: storeURL)
        environment.timing = timing
        environment.rule = SyncAddressRule { [] }
        environment.advertise = false
        environment.makeDiscovery = { [weak self] context in
            let discovery = StaticDiscovery(context: context)
            self?.discovery = discovery
            return discovery
        }
        environment.claimLaunch = { [weak self] in
            guard let self else { return false }
            defer { self.launched = true }
            return !self.launched
        }
        let created = CookieSyncService(account: account, source: source, environment: environment)
        service = created
        created.start()
    }

    /// Quits the process: the run stops and the engine loses its session cookies.
    func restart() {
        service?.stop()
        service = nil
        discovery = nil
        source.dropSessionCookies()
        launched = false
        boot()
    }

    func shutDown() {
        service?.stop()
        service = nil
    }

    var advert: SyncAdvert? {
        guard let run = service?.run, let port = service?.listenerPort, let subject = account.subject,
              let hint = try? SyncStoreBridge.accountHints(subject: subject, now: Int64(Date().timeIntervalSince1970 * 1_000)).current,
              let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }
        return SyncAdvert(replica: run.replica, hint: hint, name: name, endpoint: .hostPort(host: "127.0.0.1", port: endpointPort))
    }

    func status() async -> [String: Any] { await service?.status() ?? [:] }
}

@MainActor
func eventually(
    _ what: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line,
    _ condition: @MainActor () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Timed out waiting for \(what)", file: file, line: line)
}

/// Sends raw bytes to a loopback port and returns the status and how long the answer took.
func rawRequest(port: UInt16, _ bytes: Data, timeout: TimeInterval = 10) async -> (status: Int?, seconds: TimeInterval) {
    let started = Date()
    guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return (nil, 0) }
    let connection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
    let status: Int? = await withCheckedContinuation { continuation in
        let lock = NSLock()
        var done = false
        var buffer = Data()
        func finish(_ value: Int?) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            connection.cancel()
            continuation.resume(returning: value)
        }
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { content, _, complete, error in
                if let content { buffer.append(content) }
                if let response = SyncHTTPResponse.parse(buffer, complete: complete) { return finish(response.status) }
                if complete || error != nil { return finish(nil) }
                receive()
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: connection.send(content: bytes, completion: .contentProcessed { _ in receive() })
            case .failed, .cancelled: finish(nil)
            default: break
            }
        }
        connection.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
    }
    return (status, Date().timeIntervalSince(started))
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-sync-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
