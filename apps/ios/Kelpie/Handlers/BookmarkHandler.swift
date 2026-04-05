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
        successResponse(["bookmarks": BookmarkStore.shared.toJSON()])
    }

    @MainActor
    private func add(_ body: [String: Any]) async -> [String: Any] {
        guard let url = body["url"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "url is required")
        }
        let title = body["title"] as? String ?? url
        BookmarkStore.shared.add(title: title, url: url)
        return successResponse(["bookmarks": BookmarkStore.shared.toJSON()])
    }

    @MainActor
    private func remove(_ body: [String: Any]) async -> [String: Any] {
        guard let idStr = body["id"] as? String, let id = UUID(uuidString: idStr) else {
            return errorResponse(code: "MISSING_PARAM", message: "id is required")
        }
        BookmarkStore.shared.remove(id: id)
        return successResponse(["bookmarks": BookmarkStore.shared.toJSON()])
    }

    @MainActor
    private func clear() async -> [String: Any] {
        BookmarkStore.shared.removeAll()
        return successResponse(["cleared": true])
    }
}
