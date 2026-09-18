import Foundation

/// Persistent partition-string to data-store-UUID mapping.
///
/// `WKWebsiteDataStore(forIdentifier:)` is keyed by UUID, but callers name
/// partitions with free-form strings, so the app owns the translation and must
/// keep it across launches. Stored in `UserDefaults` — the project forbids the
/// Keychain outright.
///
/// This type is deliberately free of WebKit and of the main actor: it holds the
/// decode, dedupe, and reconciliation policy, which is the part worth testing
/// without a live WebKit environment. `PartitionRegistry` owns everything that
/// touches the engine.
struct PartitionMap: Equatable {
    /// Synthesised id prefix for an engine data store with no map entry, so an
    /// operator can see and delete it through the normal endpoints.
    static let orphanPrefix = "orphan:"

    /// `WKWebsiteDataStore(forIdentifier:)` raises on the all-zero UUID rather
    /// than returning nil, so a corrupted map entry holding it would crash the
    /// app on the next resolve. Rejected at decode instead.
    private static let zeroIdentifier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private(set) var identifiers: [String: UUID]

    init(identifiers: [String: UUID] = [:]) {
        self.identifiers = identifiers
    }

    // MARK: - Encoding

    /// Decode the `UserDefaults` representation, dropping anything malformed.
    ///
    /// Returns the recovered map plus a human-readable warning per dropped
    /// entry. A corrupt map degrades to a smaller map, never to a crash: the
    /// recovery policy is "log and carry on", with the reconciliation pass
    /// cleaning up whatever is left dangling.
    static func decode(_ raw: [String: String]) -> (map: Self, warnings: [String]) {
        var identifiers: [String: UUID] = [:]
        var seen: [UUID: String] = [:]
        var warnings: [String] = []

        // Sorted so a duplicate UUID resolves to the same survivor on every
        // launch. Dictionary order is not stable, and silently alternating
        // between two partitions claiming one store would be worse than either
        // choice: the first id alphabetically keeps the store.
        for id in raw.keys.sorted() {
            guard let value = raw[id] else { continue }
            guard let uuid = UUID(uuidString: value), uuid != Self.zeroIdentifier else {
                warnings.append("partition \"\(id)\" has an unusable store id \"\(value)\" — dropped")
                continue
            }
            if let owner = seen[uuid] {
                warnings.append("partition \"\(id)\" duplicates the store of \"\(owner)\" — dropped")
                continue
            }
            seen[uuid] = id
            identifiers[id] = uuid
        }
        return (Self(identifiers: identifiers), warnings)
    }

    /// The `UserDefaults` representation.
    func encoded() -> [String: String] {
        identifiers.mapValues(\.uuidString)
    }

    // MARK: - Lookup and mutation

    func identifier(for id: String) -> UUID? {
        identifiers[id]
    }

    /// Returns the existing store id for `id`, minting and recording a new one
    /// when the partition is seen for the first time.
    mutating func makeIdentifier(for id: String) -> UUID {
        if let existing = identifiers[id] { return existing }
        let created = UUID()
        identifiers[id] = created
        return created
    }

    mutating func remove(_ id: String) {
        identifiers.removeValue(forKey: id)
    }

    // MARK: - Reconciliation

    /// Map entries whose data store no longer exists in the engine.
    ///
    /// `liveIds` are partitions with at least one open tab; those are never
    /// reported even when the engine has not materialised their store yet,
    /// because a store is only created on disk once a web view writes to it.
    /// Dropping one of those would fork the user's identity under the same
    /// name, which the plan explicitly forbids.
    func danglingIds(engineIdentifiers: Set<UUID>, liveIds: Set<String>) -> [String] {
        identifiers
            .filter { !engineIdentifiers.contains($0.value) && !liveIds.contains($0.key) }
            .map(\.key)
            .sorted()
    }

    /// Engine data stores with no map entry — left behind by a crash, a failed
    /// delete, or a map that had to be rebuilt.
    func orphans(engineIdentifiers: Set<UUID>) -> [UUID] {
        let known = Set(identifiers.values)
        return engineIdentifiers.subtracting(known).sorted { $0.uuidString < $1.uuidString }
    }

    /// The id an orphaned store is exposed under in `get-partitions`.
    static func orphanId(for identifier: UUID) -> String {
        "\(orphanPrefix)\(identifier.uuidString)"
    }

    /// Parses `orphan:<uuid>` back into its store id, or `nil` when the string
    /// is an ordinary partition id.
    static func orphanIdentifier(from id: String) -> UUID? {
        guard id.hasPrefix(orphanPrefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(orphanPrefix.count)))
    }
}
