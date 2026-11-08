import Foundation

/// API handler for navigation history: list, clear.
struct HistoryHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("history-list") { body in await list(body) }
        router.register("history-clear") { _ in await clear() }
    }

    @MainActor
    private func list(_ body: [String: Any]) async -> [String: Any] {
        let limit = body["limit"] as? Int ?? 100
        let entries = HistoryStore.shared.toJSON()
        let sliced = Array(entries.prefix(limit))
        return successResponse(["entries": sliced, "total": entries.count])
    }

    @MainActor
    private func clear() async -> [String: Any] {
        HistoryStore.shared.clear()
        return successResponse(["cleared": true])
    }
}
