import CryptoKit
import Foundation
import Network

/// Timing of the sync service. Tests shorten these; production uses `standard`.
struct SyncTiming {
    var warmupMinimum: TimeInterval = 15
    var warmupMaximum: TimeInterval = 30
    var initiatorFallback: TimeInterval = 15
    var scanQuiet: TimeInterval = 1
    var sessionMillis: Int64 = 600_000
    var pendingMillis: Int64 = 60_000
    var pullWaitMillis = 25_000
    var warmingRetry: TimeInterval = 1
    var backoffMinimum: TimeInterval = 5
    var backoffMaximum: TimeInterval = 300

    static let standard = Self()
}

/// Protocol limits shared by every platform.
enum SyncLimits {
    static let maxClockSkewMillis: Int64 = 120_000
    static let maxPendingHandshakes = 8
    static let helloPerSource = 10
    static let helloTotal = 60
    static let outgoingHandshakes = 10
    static let concurrentUOACalls = 2
    static let maxPullWaitMillis = 25_000
}

/// One live encrypted session with a peer. Only the initiator sends requests.
@MainActor
final class SyncChannel {
    enum Role: Equatable {
        case initiator(NWEndpoint)
        case responder
    }

    let sessionId: String
    let peer: String
    let role: Role
    let sendKey: SymmetricKey
    let receiveKey: SymmetricKey
    let expiresAt: Int64
    /// Initiator: the last request sequence number used.
    var lastSeq: UInt64 = 0
    /// Responder: which request sequence numbers were already accepted.
    var replay = SyncReplayWindow()
    /// Initiator: the responder's last `yourWatermark`, where the next push starts.
    var yourWatermark: [String: Any]?
    var pushing = false
    var pushAgain = false
    private(set) var closed = false
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(sessionId: String, peer: String, role: Role, sendKey: SymmetricKey, receiveKey: SymmetricKey, expiresAt: Int64) {
        self.sessionId = sessionId
        self.peer = peer
        self.role = role
        self.sendKey = sendKey
        self.receiveKey = receiveKey
        self.expiresAt = expiresAt
    }

    var isInitiator: Bool { role != .responder }

    var endpoint: NWEndpoint? {
        guard case .initiator(let endpoint) = role else { return nil }
        return endpoint
    }

    /// Runs `body` until it finishes or the session closes.
    func spawn(_ body: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await body()
            self?.tasks.removeValue(forKey: id)
        }
        if closed { task.cancel() } else { tasks[id] = task }
    }

    func close() {
        closed = true
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

/// A responder's handshake between `hello` and `auth`. Consumed by the first `auth`.
struct SyncPendingHandshake {
    let id: String
    let peer: String
    let platform: String
    let name: String
    let peerKey: P256.KeyAgreement.PublicKey
    let privateKey: P256.KeyAgreement.PrivateKey
    let challenge: String
    let expiresAt: Int64
}

/// What this run knows about one peer replica. Never holds cookie data.
@MainActor
final class SyncPeer {
    enum State: String {
        case waiting, connecting, connected, retrying, offline
    }

    let replica: String
    var platform = ""
    var name = ""
    var advert: SyncAdvert?
    /// When the peer was first seen, or when its last session ended.
    var quietSince: Date
    var handshaking = false
    var failures = 0
    var retryAt: Date?
    var lastSyncAt: Int64?
    var lastError: String?
    var timer: Task<Void, Never>?

    init(replica: String, now: Date) {
        self.replica = replica
        quietSince = now
    }
}

/// Everything that belongs to one open store: one subject, one generation, one replica.
/// Tearing a run down cancels its tasks, stops its listener and discovery and wakes its
/// long polls; the store is closed after any open transaction finishes.
@MainActor
final class SyncRun {
    let fence: SyncFence
    let replica: String
    let store: SyncStoreBridge
    let launchedAt = Date()
    var warming: Bool
    var warmupPeers: Set<String> = []
    var warmupDone: Set<String> = []
    var listener: SyncListener?
    var port: UInt16?
    var discovery: SyncDiscovery?
    var peers: [String: SyncPeer] = [:]
    var channels: [String: SyncChannel] = [:]
    var pending: [SyncPendingHandshake] = []
    var helloLimiter = SyncRateLimiter(perKey: SyncLimits.helloPerSource, total: SyncLimits.helloTotal)
    var outgoingLimiter = SyncRateLimiter(perKey: SyncLimits.outgoingHandshakes, total: SyncLimits.outgoingHandshakes)
    let changes = SyncChangeSignal()
    /// Responder pulls that hold records and have not answered yet.
    var answering = 0
    var scanTask: Task<Void, Never>?
    private(set) var cancelled = false
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(fence: SyncFence, replica: String, store: SyncStoreBridge, warming: Bool) {
        self.fence = fence
        self.replica = replica
        self.store = store
        self.warming = warming
    }

    func peer(_ replica: String) -> SyncPeer {
        if let existing = peers[replica] { return existing }
        let created = SyncPeer(replica: replica, now: Date())
        peers[replica] = created
        return created
    }

    func channel(for peer: String) -> SyncChannel? { channels.values.first { $0.peer == peer } }

    var initiatorChannels: [SyncChannel] { channels.values.filter(\.isInitiator) }

    /// One session per pair: a new session replaces any other with the same peer.
    func install(_ channel: SyncChannel) {
        for other in channels.values where other.peer == channel.peer { remove(other) }
        channels[channel.sessionId] = channel
    }

    func remove(_ channel: SyncChannel) {
        guard channels[channel.sessionId] === channel else { return }
        channels.removeValue(forKey: channel.sessionId)
        channel.close()
    }

    /// At most eight pending handshakes; a new one evicts the oldest.
    func addPending(_ handshake: SyncPendingHandshake) {
        pending.append(handshake)
        if pending.count > SyncLimits.maxPendingHandshakes { pending.removeFirst(pending.count - SyncLimits.maxPendingHandshakes) }
    }

    func takePending(_ id: String) -> SyncPendingHandshake? {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
        return pending.remove(at: index)
    }

    /// Runs `body` until it finishes or the run is torn down.
    func spawn(_ body: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await body()
            self?.tasks.removeValue(forKey: id)
        }
        if cancelled { task.cancel() } else { tasks[id] = task }
    }

    func cancel() {
        cancelled = true
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        scanTask?.cancel()
        peers.values.forEach { $0.timer?.cancel() }
        channels.values.forEach { $0.close() }
        channels.removeAll()
        pending.removeAll()
        listener?.stop()
        listener = nil
        discovery?.stop()
        discovery = nil
        changes.fire()
    }
}
