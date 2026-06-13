import Foundation
import Security
import CryptoKit

/// State + storage for the pairing/auth system on iOS.
///
/// Persistent state (token hashes only) is written atomically to
/// `<AppSupport>/Kelpie/pairings.json` with `NSFileProtectionComplete`.
/// In-memory state (pending requests, session tokens, denied addresses)
/// lives only for the lifetime of the app process.
///
/// All public methods are safe to call from any thread; access is serialised
/// through `NSLock`. The store is intentionally synchronous because writes are
/// rare (a few per pairing approval) and reads are on the request path —
/// dispatching to a serial queue would add latency for no real gain.
final class PairingStore: @unchecked Sendable {
    /// On-disk persistent record (file storage; no encryption — hashes only).
    struct PairingRecord: Codable, Equatable {
        let clientId: String
        let clientName: String
        let tokenHashSha256: String  // hex
        let approvedAt: Double       // ms since epoch
        var lastSeenAt: Double       // ms since epoch
    }

    /// In-memory pending pairing request awaiting user action.
    struct PendingRequest: Equatable {
        let requestId: String
        let clientId: String
        let clientName: String
        let sourceAddress: String
        let createdAt: Double
        let expiresAt: Double
    }

    /// In-memory session approval ("Yes once" — cleared on app restart).
    struct SessionApproval: Equatable {
        let clientId: String
        let clientName: String
        let tokenHashSha256: String
        let approvedAt: Double
    }

    static let pendingTTLSeconds: Double = 300       // 5 min
    static let denyTTLSeconds: Double = 600          // 10 min suppression
    static let clientNameMaxLength = 64

    private let lock = NSLock()
    private let storeURL: URL?

    /// Persistent pairings (token hashes only).
    private var persistent: [PairingRecord] = []
    /// In-memory session approvals (cleared on restart).
    private var sessions: [SessionApproval] = []
    /// Pending pair requests keyed by requestId.
    private var pending: [String: PendingRequest] = [:]
    /// Source-address suppression: addr → expiresAt (ms).
    private var deniedSources: [String: Double] = [:]
    /// One visible pending request per source address. addr → requestId.
    private var pendingBySource: [String: String] = [:]
    /// Pending issuances: an approved pairing has produced a token; the next
    /// status poll for that requestId from the originating source receives it
    /// exactly once and the entry is deleted.
    private var pendingIssuances: [String: PendingIssuance] = [:]

    struct PendingIssuance {
        let token: String
        let scope: String  // "session" or "persistent"
        let sourceAddress: String
        let createdAt: Double
        let expiresAt: Double
    }

    init(storeURL: URL? = PairingStore.defaultStoreURL()) {
        self.storeURL = storeURL
        load()
    }

    // MARK: - Disk layout

    static func defaultStoreURL() -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = support.appendingPathComponent("Kelpie", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir.appendingPathComponent("pairings.json")
    }

    private func load() {
        guard let storeURL, FileManager.default.fileExists(atPath: storeURL.path) else { return }
        guard let data = try? Data(contentsOf: storeURL) else { return }
        guard let envelope = try? JSONDecoder().decode(StoredEnvelope.self, from: data) else { return }
        lock.lock()
        defer { lock.unlock() }
        persistent = envelope.pairings
    }

    private func persistLocked() {
        guard let storeURL else { return }
        let envelope = StoredEnvelope(version: 1, pairings: persistent)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        // Atomic write: temp + fsync + rename.
        let tmpURL = storeURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmpURL, options: [.atomic])
            // Apply file protection so the file is unreadable while the device is locked.
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600],
                ofItemAtPath: tmpURL.path
            )
            if FileManager.default.fileExists(atPath: storeURL.path) {
                _ = try? FileManager.default.replaceItemAt(storeURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: storeURL)
            }
        } catch {
            print("[PairingStore] Failed to persist: \(error)")
        }
    }

    private struct StoredEnvelope: Codable {
        let version: Int
        let pairings: [PairingRecord]
    }

    // MARK: - Token sanitisation helpers

    static func sanitizeClientName(_ raw: String) -> String {
        let stripped = raw.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map { Character($0) }
        let truncated = String(stripped.prefix(clientNameMaxLength))
        return truncated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Hex-encoded SHA-256 of the bearer plaintext, used for both server-side
    /// comparison and on-disk storage. Constant-time comparison is performed
    /// on the 32-byte digest below.
    static func hashToken(_ plaintext: String) -> String {
        let digest = SHA256.hash(data: Data(plaintext.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time compare for two hex SHA-256 digests of equal length.
    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<lhsBytes.count { diff |= lhsBytes[i] ^ rhsBytes[i] }
        return diff == 0
    }

    /// Cryptographically secure random base64url-encoded 32-byte string.
    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // SecRandom must succeed on supported platforms; if it ever fails
            // we refuse to issue weak tokens.
            fatalError("SecRandomCopyBytes failed with status \(status)")
        }
        return base64URLEncode(Data(bytes))
    }

    static func generateRequestId() -> String {
        generateToken()  // same primitive — both are 32-byte CSPRNG nonces
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Pending requests (POST /v1/pair)

    /// Result of starting a new pair request.
    enum PairStartResult {
        case created(PendingRequest)
        case denied  // source address in suppression window
    }

    /// Returns a fresh pending entry, or `denied` if this source address is in
    /// the current 10-minute denial window. Same source + same clientId is
    /// idempotent (replaces the prior pending entry).
    func startPairing(clientId: String, clientName: String, sourceAddress: String) -> PairStartResult {
        lock.lock()
        defer { lock.unlock() }

        gcLocked(now: nowMs())

        if let expiresAt = deniedSources[sourceAddress], expiresAt > nowMs() {
            return .denied
        }

        // Coalesce: if this source already has a visible pending prompt,
        // replace it. Spammers from one source cannot accumulate.
        if let existingId = pendingBySource[sourceAddress] {
            pending.removeValue(forKey: existingId)
        }

        let req = PendingRequest(
            requestId: Self.generateRequestId(),
            clientId: clientId,
            clientName: Self.sanitizeClientName(clientName),
            sourceAddress: sourceAddress,
            createdAt: nowMs(),
            expiresAt: nowMs() + Self.pendingTTLSeconds * 1_000
        )
        pending[req.requestId] = req
        pendingBySource[sourceAddress] = req.requestId
        return .created(req)
    }

    /// Visible pending requests, oldest first. UI uses this to drive the prompt
    /// stack — one visible prompt per source at a time.
    func visiblePending() -> [PendingRequest] {
        lock.lock()
        defer { lock.unlock() }
        gcLocked(now: nowMs())
        return pending.values.sorted { $0.createdAt < $1.createdAt }
    }

    func pendingRequest(requestId: String) -> PendingRequest? {
        lock.lock()
        defer { lock.unlock() }
        gcLocked(now: nowMs())
        return pending[requestId]
    }

    /// Approve a pending request. Generates a token, writes its hash to either
    /// the persistent store or the session list, and stages the plaintext as a
    /// `PendingIssuance` keyed by `requestId`. The next status poll from the
    /// originating source consumes the issuance exactly once.
    @discardableResult
    func approve(requestId: String, persist: Bool) -> (token: String, scope: String)? {
        lock.lock()
        defer { lock.unlock() }
        gcLocked(now: nowMs())
        guard let entry = pending.removeValue(forKey: requestId) else { return nil }
        pendingBySource.removeValue(forKey: entry.sourceAddress)

        let token = Self.generateToken()
        let hash = Self.hashToken(token)
        let now = nowMs()
        let scope: String
        if persist {
            persistent.removeAll { $0.clientId == entry.clientId }
            persistent.append(
                PairingRecord(
                    clientId: entry.clientId,
                    clientName: entry.clientName,
                    tokenHashSha256: hash,
                    approvedAt: now,
                    lastSeenAt: now
                )
            )
            persistLocked()
            scope = "persistent"
        } else {
            sessions.removeAll { $0.clientId == entry.clientId }
            sessions.append(
                SessionApproval(
                    clientId: entry.clientId,
                    clientName: entry.clientName,
                    tokenHashSha256: hash,
                    approvedAt: now
                )
            )
            scope = "session"
        }
        pendingIssuances[requestId] = PendingIssuance(
            token: token,
            scope: scope,
            sourceAddress: entry.sourceAddress,
            createdAt: now,
            expiresAt: now + Self.pendingTTLSeconds * 1_000
        )
        return (token, scope)
    }

    /// Consume the pending issuance for `requestId` if the source address
    /// matches the original pair request. Token is returned exactly once.
    func takeIssuance(for requestId: String, sourceAddress: String) -> PendingIssuance? {
        lock.lock()
        defer { lock.unlock() }
        gcLocked(now: nowMs())
        guard let issuance = pendingIssuances[requestId] else { return nil }
        guard issuance.sourceAddress == sourceAddress else { return nil }
        pendingIssuances.removeValue(forKey: requestId)
        return issuance
    }

    func wasRecentlyDenied(sourceAddress: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        gcLocked(now: nowMs())
        if let exp = deniedSources[sourceAddress], exp > nowMs() { return true }
        return false
    }

    /// Deny a pending request. Suppresses re-prompts from this source address for
    /// 10 minutes (denied list is in-memory only — no persistent DoS).
    func deny(requestId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = pending.removeValue(forKey: requestId) else { return }
        pendingBySource.removeValue(forKey: entry.sourceAddress)
        deniedSources[entry.sourceAddress] = nowMs() + Self.denyTTLSeconds * 1_000
    }

    // MARK: - Token validation (request path)

    /// Validate a bearer token against persistent + session stores.
    /// Returns the matching clientId, or `nil` if not authorized.
    func validateBearer(_ token: String) -> String? {
        let hash = Self.hashToken(token)
        lock.lock()
        defer { lock.unlock() }
        if let idx = persistent.firstIndex(where: {
            Self.constantTimeEqual($0.tokenHashSha256, hash)
        }) {
            persistent[idx].lastSeenAt = nowMs()
            // We don't persist on every request — lastSeenAt is best-effort.
            return persistent[idx].clientId
        }
        if let match = sessions.first(where: {
            Self.constantTimeEqual($0.tokenHashSha256, hash)
        }) {
            return match.clientId
        }
        return nil
    }

    // MARK: - Revocation

    /// Revoke the pairing for the given clientId (called by DELETE /v1/pair).
    /// Returns true if any record was removed.
    @discardableResult
    func revoke(clientId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let before = persistent.count + sessions.count
        persistent.removeAll { $0.clientId == clientId }
        sessions.removeAll { $0.clientId == clientId }
        if persistent.count + sessions.count != before {
            persistLocked()
            return true
        }
        return false
    }

    // MARK: - Settings UI queries

    func listPersistent() -> [PairingRecord] {
        lock.lock(); defer { lock.unlock() }
        return persistent
    }

    func listSessions() -> [SessionApproval] {
        lock.lock(); defer { lock.unlock() }
        return sessions
    }

    func listDeniedSources() -> [(address: String, expiresAt: Double)] {
        lock.lock(); defer { lock.unlock() }
        gcLocked(now: nowMs())
        return deniedSources.map { ($0.key, $0.value) }
    }

    // MARK: - GC

    private func gcLocked(now: Double) {
        // Drop expired pending requests + their source mapping.
        let expiredIds = pending.values.filter { $0.expiresAt <= now }.map(\.requestId)
        for id in expiredIds {
            if let entry = pending.removeValue(forKey: id) {
                if pendingBySource[entry.sourceAddress] == id {
                    pendingBySource.removeValue(forKey: entry.sourceAddress)
                }
            }
        }
        // Drop expired denial entries + stale issuances.
        deniedSources = deniedSources.filter { $0.value > now }
        pendingIssuances = pendingIssuances.filter { $0.value.expiresAt > now }
    }

    private func nowMs() -> Double {
        Date().timeIntervalSince1970 * 1_000
    }
}
