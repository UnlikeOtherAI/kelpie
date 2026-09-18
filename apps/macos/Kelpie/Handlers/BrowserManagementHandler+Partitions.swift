import Foundation

/// Storage-partition endpoints and the shared partition error shapes.
///
/// Partitions are WebKit-only: CEF is a single-browser engine with no
/// equivalent of `WKWebsiteDataStore(forIdentifier:)`, so every endpoint here
/// refuses while Chromium is active — with the discriminating `reason` field
/// rather than a generic failure, so a caller can recover by switching engines.
extension BrowserManagementHandler {
    // MARK: - Endpoints

    @MainActor
    func getPartitions() async -> [String: Any] {
        if let unsupported = chromiumUnsupportedIfActive() { return unsupported }
        return successResponse(["partitions": PartitionRegistry.shared.listing()])
    }

    @MainActor
    func deletePartition(_ body: [String: Any]) async -> [String: Any] {
        if let unsupported = chromiumUnsupportedIfActive() { return unsupported }
        guard let id = body["id"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "id (partition string) required")
        }
        // `orphan:<uuid>` ids are synthesised by get-partitions and deliberately
        // fail the user-facing validator, so they are let through explicitly —
        // otherwise the only ids an operator can see would be undeletable.
        if PartitionMap.orphanIdentifier(from: id) == nil,
           let failure = PartitionValidator.validate(id) {
            return errorResponse(code: "INVALID_PARTITION", message: failure.message)
        }

        // Unknown id: idempotent success with the same response shape, so a
        // caller never has to branch on whether a teardown already happened.
        guard PartitionRegistry.shared.beginDeleting(id: id) else {
            return successResponse(["deleted": id, "tabsClosed": 0, "existed": false])
        }

        let tabsClosed = closeTabs(inPartition: id)
        do {
            try await PartitionRegistry.shared.finishDeleting(id: id)
        } catch let inUse as PartitionRegistry.PartitionInUseError {
            return errorResponse(
                code: "PARTITION_IN_USE",
                message: "The engine refused to delete partition \"\(id)\" after closing " +
                    "\(tabsClosed) tab(s): \(inUse.underlying.localizedDescription). " +
                    "The id is free to reuse; the abandoned store is now listed by " +
                    "get-partitions as orphan:<uuid> and can be deleted with that id."
            )
        } catch {
            return errorResponse(
                code: "PARTITION_IN_USE",
                message: "Failed to delete partition \"\(id)\": \(error.localizedDescription)"
            )
        }
        return successResponse(["deleted": id, "tabsClosed": tabsClosed, "existed": true])
    }

    // MARK: - Tab teardown

    /// Closes every tab bound to `id` across all windows and returns how many.
    ///
    /// Iterates a snapshot of ids rather than the live array: closing the last
    /// tab in a window replaces it with a fresh blank tab, which would
    /// invalidate indices taken mid-loop.
    @MainActor
    private func closeTabs(inPartition id: String) -> Int {
        var closed = 0
        for entry in WindowRegistry.shared.allEntriesIncludingDetached() {
            guard let callbacks = entry.callbacks else { continue }
            let doomed = entry.tabStore.tabs.filter { $0.partition == id }.map(\.id)
            for tabId in doomed {
                callbacks.onCloseTab(tabId)
                closed += 1
            }
        }
        return closed
    }

    // MARK: - Errors

    /// `PARTITION_UNSUPPORTED` when Chromium is the active engine, else `nil`.
    @MainActor
    func chromiumUnsupportedIfActive() -> [String: Any]? {
        guard context.renderer?.engineName == "chromium" else { return nil }
        return Self.partitionUnsupportedError(
            reason: "chromium-engine",
            activeEngine: "chromium",
            message: "Storage partitions are not available in Chromium (CEF) mode. " +
                "CEF has no per-tab data store; partitions require WebKit.",
            hint: "switch to webkit via set-renderer"
        )
    }

    /// The `PARTITION_UNSUPPORTED` envelope. A single error code with a
    /// machine-actionable `reason` discriminator, so a caller branches on one
    /// field instead of on message text.
    static func partitionUnsupportedError(
        reason: String,
        activeEngine: String?,
        message: String,
        hint: String
    ) -> [String: Any] {
        var error: [String: Any] = [
            "code": "PARTITION_UNSUPPORTED",
            "message": message,
            "reason": reason,
            "hint": hint
        ]
        if let activeEngine {
            error["activeEngine"] = activeEngine
        }
        return ["success": false, "error": error]
    }

    /// Maps a registry resolution failure onto its wire error.
    static func partitionResolveError(_ failure: PartitionRegistry.ResolveFailure, id: String) -> [String: Any] {
        switch failure {
        case .invalid(let reason):
            return errorResponse(
                code: "INVALID_PARTITION",
                message: "Invalid partition \"\(id)\": \(reason.message)"
            )
        case .deleting:
            return errorResponse(
                code: "PARTITION_DELETING",
                message: "Partition \"\(id)\" is being deleted. Retry once delete-partition returns."
            )
        }
    }
}
