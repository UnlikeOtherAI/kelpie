import AppKit

/// Shared context providing access to the active renderer for all handlers.
@MainActor
final class HandlerContext {
    nonisolated static let defaultOverlayRGB = "59,130,246"

    var renderer: (any RendererEngine)?
    var consoleMessages: [[String: Any]] = []
    var isIn3DInspector = false
    var scriptPlaybackState: ScriptPlaybackState?
    var annotationSessionId: String?
    var annotationPageURL: String?
    var annotationElementCount: Int?

    var sharedCookiePoller: Timer?
    var lastSharedCookieSignature: String = ""
    var lastSharedCookieModifiedAt: Date?

    init() {}

    // MARK: - Window/tab resolution

    /// Look up the window the request targets. Resolution order:
    /// 1. `windowId` body field if present (returns `nil` for unknown ids so
    ///    the caller can surface `WINDOW_NOT_FOUND`).
    /// 2. The window that owns the supplied `tabId`.
    /// 3. The current key/main window (the user's focused shell).
    func resolveWindow(windowId: String?, tabId: String?) -> WindowRegistry.Entry? {
        WindowRegistry.shared.resolveEntry(windowId: windowId, tabId: tabId)
    }

    /// Tab store for the window resolved from `windowId`/`tabId`.
    func tabStore(windowId: String?, tabId: String?) -> TabStore? {
        resolveWindow(windowId: windowId, tabId: tabId)?.tabStore
    }

    /// Resolves the renderer for a specific tab in a specific window. Multi-
    /// tab windows reject empty `tabId` so LLMs are forced to be explicit
    /// about which tab they target.
    func resolveRenderer(windowId: String?, tabId: String?) throws -> any RendererEngine {
        if let windowId, WindowRegistry.shared.entry(for: windowId) == nil {
            throw HandlerError.windowNotFound(windowId)
        }

        guard let tabId else {
            // No tabId: auto-select if the resolved window has exactly one tab,
            // otherwise require explicit targeting.
            let entry = resolveWindow(windowId: windowId, tabId: nil)
            if let store = entry?.tabStore, store.tabs.count > 1 {
                let listing = store.tabs.map { tab in
                    "\(tab.id.uuidString)  \(tab.title)  \(tab.currentURL)"
                }.joined(separator: "\n")
                throw HandlerError.tabRequired(listing)
            }
            if let tab = entry?.tabStore.activeTab {
                return tab.renderer
            }
            guard let renderer else { throw HandlerError.noWebView }
            return renderer
        }

        guard let uuid = UUID(uuidString: tabId) else {
            throw HandlerError.tabNotFound(tabId)
        }

        // If windowId is explicit, the tab must live in that window.
        if let windowId,
           let entry = WindowRegistry.shared.entry(for: windowId) {
            guard let tab = entry.tabStore.tabs.first(where: { $0.id == uuid }) else {
                throw HandlerError.tabNotFound(tabId)
            }
            return tab.renderer
        }

        // Otherwise locate the tab in any window.
        if let entry = WindowRegistry.shared.entry(containingTabId: uuid) {
            // swiftlint:disable:next force_unwrapping
            return entry.tabStore.tabs.first(where: { $0.id == uuid })!.renderer
        }
        throw HandlerError.tabNotFound(tabId)
    }

    /// Legacy single-window form retained for handlers that have not yet been
    /// updated to accept a `windowId`. Routes through the registry using the
    /// front-window default.
    func resolveRenderer(tabId: String?) throws -> any RendererEngine {
        try resolveRenderer(windowId: nil, tabId: tabId)
    }

    /// Extract tabId from a request body dict.
    nonisolated static func tabId(from body: [String: Any]) -> String? {
        body["tabId"] as? String
    }

    /// Extract windowId from a request body dict.
    nonisolated static func windowId(from body: [String: Any]) -> String? {
        body["windowId"] as? String
    }

    /// Convenience: evaluate JS on a specific tab.
    func evaluateJS(_ script: String, tabId: String?) async throws -> Any? {
        let target = try resolveRenderer(tabId: tabId)
        return try await target.evaluateJS(script)
    }

    func evaluateJSReturningString(_ script: String, tabId: String?) async throws -> String {
        let result = try await evaluateJS(script, tabId: tabId)
        return result as? String ?? String(describing: result ?? "null")
    }

    func evaluateJSReturningJSON(_ script: String, tabId: String?) async throws -> [String: Any] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped, tabId: tabId)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    func evaluateJSReturningArray(_ script: String, tabId: String?) async throws -> [[String: Any]] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped, tabId: tabId)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    func takeSnapshot(tabId: String?) async throws -> NSImage {
        let target = try resolveRenderer(tabId: tabId)
        return try await target.takeSnapshot()
    }

    func showTouchIndicator(x: Double, y: Double, color: String = defaultOverlayRGB, tabId: String?) async {
        let js = """
        (function() {
            var dot = document.createElement('div');
            dot.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'background:rgba(\(JSEscape.string(color)),0.7);pointer-events:none;z-index:2147483647;' +
                'transition:transform 0.5s ease-out, opacity 0.5s ease-out;transform:scale(1);opacity:1;';
            document.body.appendChild(dot);
            var ripple = document.createElement('div');
            ripple.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'border:2px solid rgba(\(JSEscape.string(color)),0.7);pointer-events:none;z-index:2147483647;' +
                'transition:transform 0.6s ease-out, opacity 0.6s ease-out;transform:scale(1);opacity:1;';
            document.body.appendChild(ripple);
            requestAnimationFrame(function() {
                ripple.style.transform = 'scale(3)';
                ripple.style.opacity = '0';
            });
            setTimeout(function() {
                dot.style.transform = 'scale(0.5)';
                dot.style.opacity = '0';
            }, 550);
            setTimeout(function() {
                dot.remove();
                ripple.remove();
            }, 1100);
        })();
        """
        _ = try? await evaluateJS(js, tabId: tabId)
    }

    func showTouchIndicatorForElement(
        _ selector: String,
        color: String = defaultOverlayRGB,
        tabId: String?
    ) async {
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return JSON.stringify(null);
            var r = el.getBoundingClientRect();
            return JSON.stringify({x: r.left + r.width/2, y: r.top + r.height/2});
        })()
        """
        if let result = try? await evaluateJSReturningString(js, tabId: tabId),
           let data = result.data(using: .utf8),
           let pos = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
           let x = pos["x"], let y = pos["y"] {
            await showTouchIndicator(x: x, y: y, color: color, tabId: tabId)
        }
    }

    func screenshotViewportMetrics(tabId: String?) async throws -> ScreenshotViewportMetrics {
        let result = try await evaluateJSReturningJSON("""
        (function() {
            return {
                viewportWidth: Math.max(window.innerWidth || 0, 1),
                viewportHeight: Math.max(window.innerHeight || 0, 1),
                devicePixelRatio: window.devicePixelRatio || 1
            };
        })()
        """, tabId: tabId)
        return ScreenshotViewportMetrics(
            viewportWidth: (result["viewportWidth"] as? NSNumber)?.intValue ?? 1,
            viewportHeight: (result["viewportHeight"] as? NSNumber)?.intValue ?? 1,
            devicePixelRatio: (result["devicePixelRatio"] as? NSNumber)?.doubleValue ?? 1
        )
    }

    func screenshotPayload(
        from image: NSImage,
        format: String,
        quality: Double,
        resolution: ScreenshotResolution,
        tabId: String?
    ) async throws -> [String: Any] {
        let viewport = try await screenshotViewportMetrics(tabId: tabId)
        let normalizedFormat = format == "jpeg" ? "jpeg" : "png"
        guard let bitmap = scaledBitmapRepresentation(from: image, to: resolution, using: viewport) else {
            throw HandlerError.screenshotFailed
        }
        let imageData: Data?
        if normalizedFormat == "jpeg" {
            imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        } else {
            imageData = bitmap.representation(using: .png, properties: [:])
        }
        guard let encoded = imageData else {
            throw HandlerError.screenshotFailed
        }
        return [
            "image": encoded.base64EncodedString()
        ].merging(
            viewport.metadata(
                imageWidth: bitmap.pixelsWide,
                imageHeight: bitmap.pixelsHigh,
                format: normalizedFormat,
                resolution: resolution
            )
        ) { _, new in new }
    }

    // MARK: - Script messages

    /// Called by renderers when they receive a bridge script message.
    func handleScriptMessage(name: String, body: [String: Any]) {
        switch name {
        case "kelpieConsole":
            let message = body["message"] as? String ?? body["text"] as? String ?? ""
            if message == "__kelpie_3d_exit__" && isIn3DInspector {
                Task { @MainActor in
                    await exit3DInspectorIfNeeded(notify: true)
                }
                return
            }
            consoleMessages.append(body)
            if consoleMessages.count > 5000 { consoleMessages.removeFirst() }

        case "kelpie3DSnapshot":
            if body["action"] as? String == "exit" {
                Task { @MainActor in
                    await exit3DInspectorIfNeeded(notify: true)
                }
            }

        case "kelpieNetwork":
            let entry = NetworkTrafficStore.TrafficEntry(
                id: UUID(),
                method: (body["method"] as? String ?? "GET").uppercased(),
                url: body["url"] as? String ?? "",
                statusCode: body["statusCode"] as? Int ?? 0,
                contentType: body["contentType"] as? String ?? "",
                requestHeaders: body["requestHeaders"] as? [String: String] ?? [:],
                responseHeaders: body["responseHeaders"] as? [String: String] ?? [:],
                requestBody: body["requestBody"] as? String,
                responseBody: body["responseBody"] as? String,
                startTime: Date(),
                duration: body["duration"] as? Int ?? 0,
                size: body["size"] as? Int ?? 0,
                initiator: "js"
            )
            NetworkTrafficStore.shared.append(entry)

        default:
            break
        }
    }

    // MARK: - Active-tab convenience (used by UI code, not handlers)

    func evaluateJS(_ script: String) async throws -> Any? {
        try await evaluateJS(script, tabId: nil)
    }

    func evaluateJSReturningString(_ script: String) async throws -> String {
        try await evaluateJSReturningString(script, tabId: nil)
    }

    func evaluateJSReturningJSON(_ script: String) async throws -> [String: Any] {
        try await evaluateJSReturningJSON(script, tabId: nil)
    }

    func evaluateJSReturningArray(_ script: String) async throws -> [[String: Any]] {
        try await evaluateJSReturningArray(script, tabId: nil)
    }

    func takeSnapshot() async throws -> NSImage {
        try await takeSnapshot(tabId: nil)
    }

    func showTouchIndicator(x: Double, y: Double, color: String = defaultOverlayRGB) async {
        await showTouchIndicator(x: x, y: y, color: color, tabId: nil)
    }

    func showTouchIndicatorForElement(_ selector: String, color: String = defaultOverlayRGB) async {
        await showTouchIndicatorForElement(selector, color: color, tabId: nil)
    }

    func screenshotViewportMetrics() async throws -> ScreenshotViewportMetrics {
        try await screenshotViewportMetrics(tabId: nil)
    }

    func screenshotPayload(
        from image: NSImage,
        format: String,
        quality: Double,
        resolution: ScreenshotResolution
    ) async throws -> [String: Any] {
        try await screenshotPayload(from: image, format: format, quality: quality, resolution: resolution, tabId: nil)
    }

    /// Show a toast message overlay at the bottom of the viewport.
    func showToast(_ message: String) async {
        let js = """
        (function() {
            var existing = document.getElementById('__kelpie_toast');
            if (existing) existing.remove();
            var toast = document.createElement('div');
            toast.id = '__kelpie_toast';
            toast.textContent = '\(JSEscape.string(message))';
            toast.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);' +
                'max-width:390px;width:calc(100% - 32px);padding:14px 22px;border-radius:16px;' +
                'background:rgba(0,0,0,0.5);color:#fff;font:15px/1.4 -apple-system,system-ui,sans-serif;' +
                'text-align:center;pointer-events:none;z-index:2147483647;' +
                'backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);' +
                'transition:opacity 0.3s ease-out;opacity:0;';
            document.body.appendChild(toast);
            requestAnimationFrame(function() { toast.style.opacity = '1'; });
            setTimeout(function() {
                toast.style.opacity = '0';
                setTimeout(function() { toast.remove(); }, 300);
            }, 3000);
        })();
        """
        _ = try? await evaluateJS(js)
    }

    /// Returns a structured error for any operation that requires WebKit when CEF is active.
    func cefUnsupportedError(feature: String) -> [String: Any] {
        errorResponse(
            code: "WEBKIT_ONLY",
            message: "\(feature) is not available in Chromium (CEF) mode. " +
                "CEF is a single-renderer testing engine — \(feature) requires WebKit. " +
                "To use this feature, switch first: " +
                "kelpie_set_renderer({\"engine\": \"webkit\"})"
        )
    }

    func load(url: URL) {
        WindowRegistry.shared.defaultEntry()?.callbacks?.onWillLoad()
        reset3DInspectorForNavigation()
        renderer?.load(url: url)
    }

    var currentURL: URL? { renderer?.currentURL }
    var currentTitle: String { renderer?.currentTitle ?? "" }
    var isLoadingPage: Bool { renderer?.isLoading ?? false }
    var pageCanGoBack: Bool { renderer?.canGoBack ?? false }
    var pageCanGoForward: Bool { renderer?.canGoForward ?? false }

    func goBack() {
        reset3DInspectorForNavigation()
        renderer?.goBack()
    }

    func goForward() {
        reset3DInspectorForNavigation()
        renderer?.goForward()
    }

    func reloadPage() {
        if isIn3DInspector {
            Task { @MainActor in
                await exit3DInspectorIfNeeded(notify: true)
                renderer?.reload()
            }
            return
        }
        renderer?.reload()
    }

    func hardReloadPage() {
        if isIn3DInspector {
            Task { @MainActor in
                await exit3DInspectorIfNeeded(notify: true)
                renderer?.hardReload()
            }
            return
        }
        renderer?.hardReload()
    }

    func waitForViewportSize(_ size: CGSize) async {
        guard let view = renderer?.makeView() else { return }
        let expectedWidth = size.width
        let expectedHeight = size.height

        for _ in 0..<30 {
            let bounds = view.bounds.size
            if abs(bounds.width - expectedWidth) < 0.75 &&
               abs(bounds.height - expectedHeight) < 0.75 {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    nonisolated static func hexToRGB(_ hex: String) -> String {
        let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard normalized.count == 6,
              let red = UInt8(normalized.prefix(2), radix: 16),
              let green = UInt8(normalized.dropFirst(2).prefix(2), radix: 16),
              let blue = UInt8(normalized.dropFirst(4).prefix(2), radix: 16) else {
            return defaultOverlayRGB
        }
        return "\(red),\(green),\(blue)"
    }

    func mark3DInspectorInactive(notify: Bool) {
        isIn3DInspector = false
        guard notify else { return }
        NotificationCenter.default.post(name: .snapshot3DExited, object: nil)
    }

    func exit3DInspectorIfNeeded(notify: Bool) async {
        guard isIn3DInspector else { return }
        _ = try? await evaluateJS(Snapshot3DBridge.exitScript)
        mark3DInspectorInactive(notify: notify)
    }

    private func reset3DInspectorForNavigation() {
        guard isIn3DInspector else { return }
        mark3DInspectorInactive(notify: true)
    }
}

extension Notification.Name {
    static let snapshot3DExited = Notification.Name("kelpie.snapshot3DExited")
}

enum HandlerError: Error {
    case noWebView
    case rendererHidden
    case elementNotFound(String)
    case screenshotFailed
    case timeout
    case platformNotSupported(String)
    case tabNotFound(String)
    case tabRequired(String)
    case windowNotFound(String)
}

func tabErrorResponse(from error: Error) -> [String: Any]? {
    guard let handlerError = error as? HandlerError else { return nil }
    switch handlerError {
    case .tabNotFound(let tabId):
        return errorResponse(code: "TAB_NOT_FOUND", message: "No tab with id \"\(tabId)\"")
    case .tabRequired(let listing):
        return errorResponse(
            code: "TAB_REQUIRED",
            message: "Multiple tabs open — specify \"tabId\" in your request. Available tabs:\n\(listing)"
        )
    case .windowNotFound(let windowId):
        return errorResponse(
            code: "WINDOW_NOT_FOUND",
            message: "No window with id \"\(windowId)\". Call get-tabs without windowId to list available windows."
        )
    case .rendererHidden:
        return errorResponse(
            code: "RENDERER_HIDDEN",
            message: "The active renderer is hidden — its view is detached or off-screen, " +
                "so script evaluation and DOM queries are unavailable. Bring the window " +
                "to front or switch to a renderer whose view is visible."
        )
    default:
        return nil
    }
}

func errorResponse(code: String, message: String) -> [String: Any] {
    errorResponse(code: code, message: message, diagnostics: nil)
}

func errorResponse(code: String, message: String, diagnostics: [String: Any]?) -> [String: Any] {
    var error: [String: Any] = ["code": code, "message": message]
    if let diagnostics, !diagnostics.isEmpty {
        error["diagnostics"] = diagnostics
    }
    return ["success": false, "error": error]
}

func successResponse(_ data: [String: Any] = [:]) -> [String: Any] {
    var result: [String: Any] = ["success": true]
    for (key, value) in data { result[key] = value }
    return result
}

// Cookie sync extension lives in `HandlerContext+Cookies.swift`.
