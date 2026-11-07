import Foundation

/// API handler for network inspector: list/filter traffic, get detail, navigate to entry, clear.
struct NetworkInspectorHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("network-list") { body in await list(body) }
        router.register("network-detail") { body in await detail(body) }
        router.register("network-select") { body in await select(body) }
        router.register("network-current") { _ in await current() }
        router.register("network-clear") { _ in await clear() }
    }

    @MainActor
    private func list(_ body: [String: Any]) async -> [String: Any] {
        let store = NetworkTrafficStore.shared
        let entries = store.toSummaryJSON(
            method: body["method"] as? String,
            category: body["category"] as? String,
            statusRange: body["statusRange"] as? String,
            urlPattern: body["urlPattern"] as? String
        )
        return successResponse(["entries": entries, "total": store.entries.count])
    }

    @MainActor
    private func detail(_ body: [String: Any]) async -> [String: Any] {
        let store = NetworkTrafficStore.shared
        guard let index = body["index"] as? Int, store.entries.indices.contains(index) else {
            return errorResponse(code: "INVALID_INDEX", message: "index is required and must be valid")
        }
        return successResponse(store.entryToJSON(store.entries[index]))
    }

    @MainActor
    private func select(_ body: [String: Any]) async -> [String: Any] {
        let store = NetworkTrafficStore.shared
        if let index = body["index"] as? Int, store.entries.indices.contains(index) {
            store.selectedIndex = index
            return successResponse(store.entryToJSON(store.entries[index]))
        }
        if let pattern = body["urlPattern"] as? String {
            if let idx = store.entries.lastIndex(where: { $0.url.contains(pattern) }) {
                store.selectedIndex = idx
                return successResponse(store.entryToJSON(store.entries[idx]))
            }
            return errorResponse(code: "NOT_FOUND", message: "No request matching '\(pattern)'")
        }
        return errorResponse(code: "MISSING_PARAM", message: "index or urlPattern is required")
    }

    @MainActor
    private func current() async -> [String: Any] {
        let store = NetworkTrafficStore.shared
        guard let entry = store.selectedEntry else {
            return errorResponse(code: "NONE_SELECTED", message: "No request currently selected")
        }
        return successResponse(store.entryToJSON(entry))
    }

    @MainActor
    private func clear() async -> [String: Any] {
        NetworkTrafficStore.shared.clear()
        return successResponse(["cleared": true])
    }
}
