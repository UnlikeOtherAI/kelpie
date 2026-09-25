import Foundation

/// API handler for bookmark CRUD: list, add, remove, clear.
struct BookmarkHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("bookmarks-list") { _ in await list() }
        router.register("bookmarks-add") { body in await add(body) }
        router.register("bookmarks-remove") { body in await remove(body) }
        router.register("bookmarks-clear") { _ in await clear() }
    }

    @MainActor
    private func list() async -> [String: Any] {
        await savedResponse()
    }

    @MainActor
    private func add(_ body: [String: Any]) async -> [String: Any] {
        guard let url = body["url"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "url is required")
        }
        let title = body["title"] as? String ?? url
        return await savedResponse(BookmarkStore.shared.add(title: title, url: url))
    }

    @MainActor
    private func remove(_ body: [String: Any]) async -> [String: Any] {
        guard let idStr = body["id"] as? String, let id = UUID(uuidString: idStr) else {
            return errorResponse(code: "MISSING_PARAM", message: "id is required")
        }
        return await savedResponse(BookmarkStore.shared.remove(id: id))
    }

    @MainActor
    private func clear() async -> [String: Any] {
        return await savedResponse(BookmarkStore.shared.removeAll(), cleared: true)
    }

    @MainActor
    private func savedResponse(_ operation: Task<Void, Error>? = nil, cleared: Bool = false) async -> [String: Any] {
        do {
            try await operation?.value
            return cleared ? successResponse(["cleared": true]) : successResponse(["bookmarks": BookmarkStore.shared.toJSON()])
        } catch {
            return errorResponse(code: "BOOKMARK_SYNC_FAILED", message: error.localizedDescription)
        }
    }
}
