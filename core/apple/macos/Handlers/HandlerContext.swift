@_implementationOnly import KelpieNative
import AppKit

/// Shared context providing access to the active renderer for all handlers.
@MainActor
final class HandlerContext {
    let profileID = KelpieStorage.profileID
    weak var browserRouter: Router?
    /// A remote job's isolated context can only resolve its pinned document.
    var remoteDocumentGuard: (() -> Bool)?
    var remoteNavigationReadGuard: (() -> Bool)?
    var remoteNavigationWaitGuard: (() -> Bool)?
    nonisolated static let defaultOverlayRGB = "59,130,246"

    private var fallbackRenderer: (any RendererEngine)?
    /// Server contexts follow the focused window. Job and test contexts can keep
    /// a fixed renderer without consulting the application's window registry.
    var targetsRegisteredTabs = false
    var renderer: (any RendererEngine)? {
        get {
            if targetsRegisteredTabs, let entry = WindowRegistry.shared.defaultEntry() {
                return entry.tabStore.activeRenderer
            }
            return fallbackRenderer
        }
        set { fallbackRenderer = newValue }
    }
    var rendererSwitchInProgress: (() -> Bool)?
    var activeEngineIsChromium = false
    var selectedBrowserTabID: String? {
        if activeEngineIsChromium && !targetsRegisteredTabs { return "chromium" }
        return tabStore(windowId: nil, tabId: nil)?.activeTab?.id.uuidString
    }
    var browserControlEngineName: String?
    var consoleMessages: [[String: Any]] = []
    var isIn3DInspector = false
    var scriptPlaybackState: ScriptPlaybackState?
    var annotationSessionId: String?
    var annotationPageURL: String?
    var annotationElementCount: Int?

    /// The live default cookie store; the only path agents, sync and renderer switches use.
    let defaultCookies = DefaultCookieStore(engine: .webkit)
    /// Peer-to-peer cookie sync for the standalone app; nil in embedded hosts.
    var cookieSync: MacCookieSync?

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
        try Task.checkCancellation()
        if let remoteDocumentGuard, !remoteDocumentGuard() { throw CancellationError() }
        if let browserControlEngineName, browserControlEngineName != renderer?.engineName { throw HandlerError.rendererHidden }
        if activeEngineIsChromium && !targetsRegisteredTabs {
            guard let renderer else { throw HandlerError.noWebView }
            return renderer
        }

        if let windowId, WindowRegistry.shared.entry(for: windowId) == nil {
            throw HandlerError.windowNotFound(windowId)
        }

        if tabId == nil || (activeEngineIsChromium && tabId == "chromium") {
            // No tabId: auto-select if the resolved window has exactly one tab,
            // otherwise require explicit targeting.
            let entry = resolveWindow(windowId: windowId, tabId: nil)
            if let store = entry?.tabStore, store.tabs.count > 1, !activeEngineIsChromium {
                let listing = store.tabs.map { tab in
                    "\(tab.id.uuidString)  \(tab.title)  \(tab.currentURL)"
                }.joined(separator: "\n")
                throw HandlerError.tabRequired(listing)
            }
            if let active = entry?.tabStore.activeRenderer { return active }
            guard let renderer else { throw HandlerError.noWebView }
            return renderer
        }

        guard let tabId, let uuid = UUID(uuidString: tabId),
              let entry = resolveWindow(windowId: windowId, tabId: tabId),
              let tab = entry.tabStore.tabs.first(where: { $0.id == uuid }),
              let target = entry.tabStore.renderer(for: tab) else {
            throw HandlerError.tabNotFound(tabId ?? "")
        }
        return target
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
    func evaluateJS(_ script: String, windowId: String? = nil, tabId: String?) async throws -> Any? {
        let target = try resolveRenderer(windowId: windowId, tabId: tabId)
        guard remoteDocumentGuard?() != false else { throw CancellationError() }
        let result = try await target.evaluateJS(script)
        guard remoteDocumentGuard?() != false else { throw CancellationError() }
        return result
    }

    func evaluateJSReturningString(_ script: String, windowId: String? = nil, tabId: String?) async throws -> String {
        let result = try await evaluateJS(script, windowId: windowId, tabId: tabId)
        return result as? String ?? String(describing: result ?? "null")
    }

    func evaluateJSReturningJSON(_ script: String, windowId: String? = nil, tabId: String?) async throws -> [String: Any] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped, windowId: windowId, tabId: tabId)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    func evaluateJSReturningArray(_ script: String, windowId: String? = nil, tabId: String?) async throws -> [[String: Any]] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped, windowId: windowId, tabId: tabId)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    func takeSnapshot(tabId: String?) async throws -> NSImage {
        let target = try resolveRenderer(tabId: tabId)
        guard remoteDocumentGuard?() != false else { throw CancellationError() }
        let result = try await target.takeSnapshot()
        guard remoteDocumentGuard?() != false else { throw CancellationError() }
        return result
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
                "\(feature) requires WebKit. " +
                "To use this feature, switch first: " +
                "kelpie_set_renderer({\"engine\": \"webkit\"})"
        )
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
        _ = try? await evaluate3DInspectorJS(Snapshot3DBridge.exitScript)
        mark3DInspectorInactive(notify: notify)
    }
}

// Error/response helpers live in `HandlerResponses.swift`.
// Cookie sync extension lives in `HandlerContext+Cookies.swift`.
