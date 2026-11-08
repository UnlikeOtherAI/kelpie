import Foundation

/// UI and MCP use the same validated tree mutations, including account CAS retries.
struct BookmarkHandler {
    let context: HandlerContext

    func register(on router: Router) {
        for method in ["list", "add", "create-folder", "update", "move", "remove", "clear"] {
            router.register("bookmarks-\(method)") { body in await handle(method, body: body) }
        }
    }

    @MainActor
    private func handle(_ method: String, body: [String: Any]) async -> [String: Any] {
        let store = BookmarkStore.shared
        do {
            let mutation: BookmarkTree.Mutation?
            switch method {
            case "list": mutation = nil
            case "add", "create-folder":
                let folder = method == "create-folder"
                guard folder || body["url"] is String else { throw BookmarkTree.Failure(message: "url is required") }
                let url = body["url"] as? String ?? ""
                let title = body["title"] as? String ?? url
                mutation = .add(BookmarkStore.Bookmark(
                    title: title,
                    url: url,
                    kind: folder ? .folder : .bookmark,
                    parentId: try uuid("parentId", in: body, required: false)
                ))
            case "update":
                guard body["title"] is String || body["url"] is String else { throw BookmarkTree.Failure(message: "title or url is required") }
                mutation = .update(try requiredID(body), title: try text("title", in: body), url: try text("url", in: body))
            case "move":
                guard body.keys.contains("parentId") else { throw BookmarkTree.Failure(message: "parentId is required; use null for the top level") }
                mutation = .move(
                    try requiredID(body),
                    parentId: try uuid("parentId", in: body, required: false),
                    beforeId: try uuid("beforeId", in: body, required: false)
                )
            case "remove":
                let id = try requiredID(body)
                guard store.nodes.contains(where: { $0.id == id }) else { throw BookmarkTree.Failure(message: "This favourite no longer exists") }
                mutation = .removeTree(BookmarkTree.subtree(id, in: store.nodes))
            case "clear": mutation = .clear
            default: throw BookmarkTree.Failure(message: "Unknown bookmarks operation")
            }
            if let mutation { try await store.mutate(mutation)?.value }
            return successResponse(method == "clear" ? ["cleared": true, "bookmarks": store.toJSON()] : ["bookmarks": store.toJSON()])
        } catch let error as BookmarkTree.Failure {
            return errorResponse(code: "INVALID_PARAM", message: error.localizedDescription)
        } catch {
            return errorResponse(code: "BOOKMARK_SYNC_FAILED", message: error.localizedDescription)
        }
    }

    private func requiredID(_ body: [String: Any]) throws -> UUID {
        guard let id = try uuid("id", in: body, required: true) else { throw BookmarkTree.Failure(message: "id is required") }
        return id
    }
    private func uuid(_ field: String, in body: [String: Any], required: Bool) throws -> UUID? {
        guard let value = body[field], !(value is NSNull) else {
            if required { throw BookmarkTree.Failure(message: "\(field) is required") }
            return nil
        }
        guard let string = value as? String, let id = UUID(uuidString: string) else { throw BookmarkTree.Failure(message: "\(field) must be a UUID") }
        return id
    }
    private func text(_ field: String, in body: [String: Any]) throws -> String? {
        guard let value = body[field] else { return nil }
        guard let text = value as? String else { throw BookmarkTree.Failure(message: "\(field) must be text") }
        return text
    }
}
