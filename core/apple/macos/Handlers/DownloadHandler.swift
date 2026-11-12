import Foundation

/// Handles `download` (save a URL through a tab's session) and
/// `get-downloads` (state of page- and agent-started downloads).
struct DownloadHandler {
    let context: HandlerContext
    /// The store the renderers record into; tests supply their own.
    var downloads: DownloadStore?

    func register(on router: Router) {
        router.register("download") { body in await download(body) }
        router.register("get-downloads") { body in await getDownloads(body) }
    }

    @MainActor
    private func download(_ body: [String: Any]) async -> [String: Any] {
        guard let urlString = body["url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return errorResponse(code: "INVALID_URL", message: "url must be an http or https URL")
        }
        let renderer: any RendererEngine
        do {
            renderer = try context.resolveRenderer(
                windowId: HandlerContext.windowId(from: body),
                tabId: HandlerContext.tabId(from: body)
            )
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
        guard let webKit = renderer as? WKWebViewRenderer else {
            return errorResponse(code: "WEBKIT_ONLY", message: "Downloads are available with the WebKit renderer")
        }
        let tabId = webKit.downloadTabId
        let tracker = webKit.downloadStore
        let record = await webKit.startDownload(url: url) { download in
            tracker.track(download, tabId: tabId, origin: .agent)
        }
        return successResponse(["download": record.json])
    }

    @MainActor
    private func getDownloads(_ body: [String: Any]) async -> [String: Any] {
        if let id = body["id"] as? String {
            guard let record = (downloads ?? .shared).record(id: id) else {
                return errorResponse(code: "NOT_FOUND", message: "No download with id \"\(id)\"")
            }
            return successResponse(["downloads": [record.json]])
        }
        return successResponse(["downloads": (downloads ?? .shared).list().map(\.json)])
    }
}
