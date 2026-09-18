import AppKit
import Foundation
import WebKit

/// Owns the live storage partitions: partition string to `WKWebsiteDataStore`,
/// the persisted string-to-UUID map, and the teardown state machine.
///
/// Everything here runs on the main actor, like the rest of the app, so
/// `new-tab` and `delete-partition` serialise against each other. They still
/// interleave at `await` points, which is exactly what the `deleting` flag
/// guards: once a teardown starts, `resolve` refuses the id until the engine
/// has finished removing the store.
///
/// `tabCount` is never stored. It is counted from the live tab list on demand,
/// so a crash, a session restore, or a window closing can never leave a stale
/// refcount pinning a partition that has no tabs.
@MainActor
final class PartitionRegistry {
    static let shared = PartitionRegistry()

    /// A resolved partition, ready to be handed to a new tab's renderer.
    struct Resolution {
        let id: String
        let dataStore: WKWebsiteDataStore
        let persistent: Bool
    }

    /// Why a partition could not be resolved for a new tab.
    enum ResolveFailure: Error {
        /// The string failed the shared validator.
        case invalid(PartitionValidator.Failure)
        /// A `delete-partition` for this id is mid-flight. The caller retries.
        case deleting
    }

    /// The engine refused to remove the store even after every tab was closed.
    struct PartitionInUseError: Error {
        let id: String
        let underlying: Error
    }

    private struct Entry {
        /// `nil` for non-persistent partitions — they have no on-disk store and
        /// so no engine identifier to persist or remove.
        let identifier: UUID?
        let dataStore: WKWebsiteDataStore
        let persistent: Bool
        var deleting = false
    }

    private static let mapDefaultsKey = "com.kelpie.partition-map"

    private var entries: [String: Entry] = [:]
    private var map: PartitionMap
    /// Engine stores with no map entry, surfaced by `get-partitions` under
    /// `orphan:<uuid>` so an operator can clean them up.
    private var orphanIdentifiers: Set<UUID> = []

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.mapDefaultsKey) as? [String: String] ?? [:]
        let decoded = PartitionMap.decode(raw)
        map = decoded.map
        for warning in decoded.warnings {
            print("[PartitionRegistry] \(warning)")
        }
        if decoded.map.encoded() != raw {
            persistMap()
        }
    }

    // MARK: - Resolution

    /// Resolve a partition string to the data store a new tab should use,
    /// creating the partition the first time it is named.
    ///
    /// The first resolve in a session fixes the partition's persistence: a
    /// later tab naming the same id joins the existing store and gets the
    /// existing flag, whatever it asked for. That is deliberate — two tabs in
    /// one partition must share storage, and there is no coherent way to share
    /// a store that is on disk for one tab and in memory for the other. The
    /// caller is not left guessing: `Resolution.persistent` reports what it
    /// actually got, and `get-tabs` echoes it back.
    func resolve(id: String, persistent: Bool) throws -> Resolution {
        if let failure = PartitionValidator.validate(id) {
            throw ResolveFailure.invalid(failure)
        }
        if let existing = entries[id] {
            guard !existing.deleting else { throw ResolveFailure.deleting }
            return Resolution(id: id, dataStore: existing.dataStore, persistent: existing.persistent)
        }

        let entry: Entry
        if persistent {
            let identifier = map.makeIdentifier(for: id)
            persistMap()
            entry = Entry(
                identifier: identifier,
                dataStore: WKWebsiteDataStore(forIdentifier: identifier),
                persistent: true
            )
        } else {
            // Non-persistent partitions never touch the map: an in-memory store
            // has no identifier to reuse on the next launch, and persisting one
            // would resurrect a partition the caller asked to keep transient.
            entry = Entry(
                identifier: nil,
                dataStore: WKWebsiteDataStore.nonPersistent(),
                persistent: false
            )
        }
        entries[id] = entry
        return Resolution(id: id, dataStore: entry.dataStore, persistent: entry.persistent)
    }

    /// Re-bind a partition restored from the session store.
    ///
    /// Returns `nil` when the partition is absent from the persisted map or is
    /// being torn down. The tab is then dropped rather than re-created under a
    /// fresh UUID, which would silently fork the user's identity under a
    /// familiar name.
    func rebind(id: String) -> Resolution? {
        if let existing = entries[id] {
            guard !existing.deleting else { return nil }
            return Resolution(id: id, dataStore: existing.dataStore, persistent: existing.persistent)
        }
        guard let identifier = map.identifier(for: id) else { return nil }
        let entry = Entry(
            identifier: identifier,
            dataStore: WKWebsiteDataStore(forIdentifier: identifier),
            persistent: true
        )
        entries[id] = entry
        return Resolution(id: id, dataStore: entry.dataStore, persistent: true)
    }

    // MARK: - Listing

    /// Every live partition plus any orphaned engine store, ordered by id.
    ///
    /// `sizeBytes` is omitted throughout: `WKWebsiteDataStore` has no cheap
    /// size API, and the contract says to omit rather than guess.
    func listing() -> [[String: Any]] {
        var rows: [[String: Any]] = entries.keys.sorted().map { id -> [String: Any] in
            [
                "id": id,
                "tabCount": tabCount(for: id),
                "persistent": entries[id]?.persistent ?? true
            ]
        }
        rows.append(contentsOf: sortedOrphans().map { identifier -> [String: Any] in
            [
                "id": PartitionMap.orphanId(for: identifier),
                "tabCount": 0,
                "persistent": true
            ]
        })
        return rows
    }

    /// Open tabs bound to `id`, counted across every window.
    func tabCount(for id: String) -> Int {
        WindowRegistry.shared.allEntries()
            .reduce(0) { total, entry in
                total + entry.tabStore.tabs.filter { $0.partition == id }.count
            }
    }

    // MARK: - Deletion

    /// Mark a partition as being torn down so no new tab binds to its store.
    ///
    /// Returns `false` when the id names nothing deletable, which is not an
    /// error — `delete-partition` is idempotent.
    func beginDeleting(id: String) -> Bool {
        if entries[id] != nil {
            entries[id]?.deleting = true
            return true
        }
        guard let identifier = PartitionMap.orphanIdentifier(from: id) else { return false }
        return orphanIdentifiers.contains(identifier)
    }

    /// Remove the engine store and drop the registry entry. Call only after
    /// every tab bound to the partition has been closed.
    ///
    /// On failure the `deleting` flag is cleared and `PartitionInUseError` is
    /// thrown, so the partition stays usable and a retry can try again rather
    /// than leaving an id that is permanently unbindable.
    func finishDeleting(id: String) async throws {
        do {
            if let identifier = PartitionMap.orphanIdentifier(from: id) {
                try await removeStore(identifier: identifier, id: id)
                orphanIdentifiers.remove(identifier)
                return
            }
            if let identifier = entries[id]?.identifier {
                try await removeStore(identifier: identifier, id: id)
            }
            // A non-persistent partition has no on-disk store; dropping the
            // entry below releases the in-memory one.
            entries.removeValue(forKey: id)
            map.remove(id)
            persistMap()
        } catch {
            entries[id]?.deleting = false
            throw error
        }
    }

    private func removeStore(identifier: UUID, id: String) async throws {
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: identifier)
        } catch {
            // WebKit refuses while a web view still references the store. Tab
            // teardown is not instantaneous, so give the run loop a turn to
            // release it before reporting the partition as stuck.
            try? await Task.sleep(nanoseconds: 300_000_000)
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: identifier)
            } catch {
                throw PartitionInUseError(id: id, underlying: error)
            }
        }
    }

    // MARK: - Reconciliation

    /// One-shot startup pass: drop map entries whose engine store has vanished
    /// and record engine stores the map does not know about.
    ///
    /// Purely corrective. `resolve` and `rebind` already work from the map
    /// loaded synchronously in `init`, so a request landing mid-pass sees at
    /// worst a stale entry that this pass was about to prune.
    func reconcile() async {
        let engineIdentifiers = Set(await WKWebsiteDataStore.fetchAllDataStoreIdentifiers())
        let liveIds = livePartitionIds()

        for id in map.danglingIds(engineIdentifiers: engineIdentifiers, liveIds: liveIds) {
            print("[PartitionRegistry] partition \"\(id)\" has no engine store — dropped")
            map.remove(id)
            entries.removeValue(forKey: id)
        }
        orphanIdentifiers = Set(map.orphans(engineIdentifiers: engineIdentifiers))
        if !orphanIdentifiers.isEmpty {
            print("[PartitionRegistry] \(orphanIdentifiers.count) orphaned data store(s) listed as \(PartitionMap.orphanPrefix)<uuid>")
        }
        persistMap()
    }

    // MARK: - Private

    private func livePartitionIds() -> Set<String> {
        Set(
            WindowRegistry.shared.allEntries()
                .flatMap { $0.tabStore.tabs.compactMap(\.partition) }
        )
    }

    private func sortedOrphans() -> [UUID] {
        orphanIdentifiers.sorted { $0.uuidString < $1.uuidString }
    }

    private func persistMap() {
        UserDefaults.standard.set(map.encoded(), forKey: Self.mapDefaultsKey)
    }
}
