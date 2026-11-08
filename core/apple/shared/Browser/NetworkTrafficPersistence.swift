@_implementationOnly import KelpieNative
import Foundation

/// One pending snapshot and one serial writer, regardless of the capture rate.
/// Network payloads belong in a private file, never in CFPreferences.
final class NetworkTrafficPersistence: @unchecked Sendable {
    static let legacyKey = "kelpie_network_traffic"
    let fileURL: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.kelpie.network-persistence", qos: .utility)
    private let lock = NSLock()
    private let interval: TimeInterval
    private var pending: [NetworkTrafficStore.TrafficEntry]?
    private var scheduled = false
    private var retryDelay: TimeInterval = 1
    private var needsRecoveryCopy = false

    init(fileURL: URL = defaultURL, defaults: UserDefaults = KelpieStorage.defaults, interval: TimeInterval = 1) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.interval = interval
    }

    private static var defaultURL: URL {
        KelpieStorage.isolated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Kelpie/network/traffic.json")
    }

    var hasLegacyData: Bool { legacyData != nil }

    var legacyData: Data? {
        defaults.data(forKey: Self.legacyKey)
            ?? defaults.string(forKey: Self.legacyKey).map { Data($0.utf8) }
    }

    func load() -> Data? {
        do { return try Data(contentsOf: fileURL) } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                preserveUnreadableFile()
            }
            return nil
        }
    }

    /// Keep an unreadable old file available for recovery rather than overwrite it.
    func preserveUnreadableFile() {
        needsRecoveryCopy = true
        do { try preserveBeforeWriting() } catch {
            NSLog("[NetworkTrafficPersistence] Could not preserve unreadable history: %@", error.localizedDescription)
        }
    }

    func save(_ entries: [NetworkTrafficStore.TrafficEntry]) {
        lock.lock()
        pending = entries
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needsSchedule { schedule(after: interval) }
    }

    /// Runs after any in-flight write, so clear/termination cannot be overwritten
    /// by an older snapshot. Delayed callbacks find no pending work after a flush.
    func flush() { queue.sync { writeLatest() } }

    private func schedule(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.writeLatest() }
    }

    private func writeLatest() {
        lock.lock()
        let snapshot = pending
        pending = nil
        lock.unlock()
        guard let snapshot else { return }

        do {
            try preserveBeforeWriting()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try writePrivately(encoder.encode(snapshot))
            defaults.removeObject(forKey: Self.legacyKey)
            retryDelay = 1
        } catch {
            NSLog("[NetworkTrafficPersistence] Could not save history: %@", error.localizedDescription)
            lock.lock()
            if pending == nil { pending = snapshot }
            lock.unlock()
            retryDelay = min(60, retryDelay * 2)
        }

        lock.lock()
        scheduled = pending != nil
        let needsSchedule = scheduled
        lock.unlock()
        if needsSchedule { schedule(after: max(interval, retryDelay)) }
    }

    /// Startup marks an unreadable file before any writer is scheduled. If moving
    /// it fails, every subsequent write retries the move before replacing anything.
    private func preserveBeforeWriting() throws {
        guard needsRecoveryCopy else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let recovery = fileURL.appendingPathExtension("unreadable-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: fileURL, to: recovery)
        }
        needsRecoveryCopy = false
    }

    private func writePrivately(_ data: Data) throws {
        let manager = FileManager.default
        var directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let temporary = directory.appendingPathComponent(".traffic-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
