import AppKit

/// Shared context providing access to the active renderer for all handlers.
@MainActor
final class HandlerContext {
    var renderer: (any RendererEngine)?
    var consoleMessages: [[String: Any]] = []
    var isIn3DInspector = false

    /// Populated by BrowserView so tab handlers can drive the full tab lifecycle.
    var tabStore: TabStore?
    var onNewTab: (() -> Tab)?
    var onSwitchTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onWillLoad: (() -> Void)?
    private var sharedCookiePoller: Timer?
    private var lastSharedCookieSignature: String = ""
    private var lastSharedCookieModifiedAt: Date?

    init() {}

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

    func evaluateJS(_ script: String) async throws -> Any? {
        guard let renderer else { throw HandlerError.noWebView }
        return try await renderer.evaluateJS(script)
    }

    func evaluateJSReturningString(_ script: String) async throws -> String {
        let result = try await evaluateJS(script)
        return result as? String ?? String(describing: result ?? "null")
    }

    func evaluateJSReturningJSON(_ script: String) async throws -> [String: Any] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// Show a blue touch indicator at viewport coordinates with a ripple animation.
    func showTouchIndicator(x: Double, y: Double) async {
        let js = """
        (function() {
            var dot = document.createElement('div');
            dot.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'background:rgba(59,130,246,0.7);pointer-events:none;z-index:2147483647;' +
                'transition:transform 0.5s ease-out, opacity 0.5s ease-out;transform:scale(1);opacity:1;';
            document.body.appendChild(dot);
            var ripple = document.createElement('div');
            ripple.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'border:2px solid rgba(59,130,246,0.7);pointer-events:none;z-index:2147483647;' +
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
        try? await evaluateJS(js)
    }

    /// Show touch indicator at an element's center by selector.
    func showTouchIndicatorForElement(_ selector: String) async {
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return JSON.stringify(null);
            var r = el.getBoundingClientRect();
            return JSON.stringify({x: r.left + r.width/2, y: r.top + r.height/2});
        })()
        """
        if let result = try? await evaluateJSReturningString(js),
           let data = result.data(using: .utf8),
           let pos = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
           let x = pos["x"], let y = pos["y"] {
            await showTouchIndicator(x: x, y: y)
        }
    }

    /// Show a toast message overlay at the bottom of the viewport.
    func showToast(_ message: String) async {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        (function() {
            var existing = document.getElementById('__kelpie_toast');
            if (existing) existing.remove();
            var toast = document.createElement('div');
            toast.id = '__kelpie_toast';
            toast.textContent = '\(escaped)';
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
        try? await evaluateJS(js)
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
        onWillLoad?()
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

    func takeSnapshot() async throws -> NSImage {
        guard let renderer else { throw HandlerError.noWebView }
        return try await renderer.takeSnapshot()
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

    func allCookies() async -> [HTTPCookie] {
        guard let renderer else { return [] }
        if renderer.engineName == "chromium" {
            return SharedCookieJar.load().cookies
        }
        return await renderer.allCookies()
    }

    func setCookie(_ cookie: HTTPCookie) async {
        guard let renderer else { return }
        await renderer.setCookies([cookie])

        if renderer.engineName == "chromium" {
            var merged = SharedCookieJar.load().cookies
            merged.removeAll { existing in
                existing.domain == cookie.domain &&
                existing.path == cookie.path &&
                existing.name == cookie.name
            }
            merged.append(cookie)
            SharedCookieJar.save(cookies: merged)
            let snapshot = SharedCookieJar.load()
            lastSharedCookieSignature = snapshot.signature
            lastSharedCookieModifiedAt = snapshot.modifiedAt
            return
        }

        await persistRendererCookiesToSharedJar()
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        guard let renderer else { return }
        await renderer.deleteCookie(cookie)

        if renderer.engineName == "chromium" {
            var merged = SharedCookieJar.load().cookies
            merged.removeAll { existing in
                existing.domain == cookie.domain &&
                existing.path == cookie.path &&
                existing.name == cookie.name
            }
            SharedCookieJar.save(cookies: merged)
            let snapshot = SharedCookieJar.load()
            lastSharedCookieSignature = snapshot.signature
            lastSharedCookieModifiedAt = snapshot.modifiedAt
            return
        }

        await persistRendererCookiesToSharedJar()
    }

    func deleteAllCookies() async {
        guard let renderer else { return }
        await renderer.deleteAllCookies()

        if renderer.engineName == "chromium" {
            SharedCookieJar.save(cookies: [])
            let snapshot = SharedCookieJar.load()
            lastSharedCookieSignature = snapshot.signature
            lastSharedCookieModifiedAt = snapshot.modifiedAt
            return
        }

        await persistRendererCookiesToSharedJar()
    }

    func syncSharedCookiesIntoRenderer(force: Bool = false) async {
        guard let renderer else { return }
        let snapshot = SharedCookieJar.load()

        if !force,
           snapshot.signature == lastSharedCookieSignature,
           snapshot.modifiedAt == lastSharedCookieModifiedAt {
            return
        }

        if renderer.engineName == "chromium" && snapshot.cookies.isEmpty {
            // CEF cookie deletion is unstable during renderer switches. The
            // shared jar remains the source of truth, and Chromium no longer
            // tries to wipe its store during activation.
        } else if snapshot.modifiedAt != nil && snapshot.cookies.isEmpty {
            await renderer.deleteAllCookies()
        } else if !snapshot.cookies.isEmpty {
            await renderer.setCookies(snapshot.cookies)
        }
        lastSharedCookieSignature = snapshot.signature
        lastSharedCookieModifiedAt = snapshot.modifiedAt
    }

    func persistRendererCookiesToSharedJar() async {
        guard let renderer else { return }
        guard renderer.engineName != "chromium" else { return }
        let cookies = await renderer.allCookies()
        let signature = SharedCookieJar.signature(for: cookies)
        if signature == lastSharedCookieSignature {
            return
        }

        SharedCookieJar.save(cookies: cookies)
        let snapshot = SharedCookieJar.load()
        lastSharedCookieSignature = snapshot.signature
        lastSharedCookieModifiedAt = snapshot.modifiedAt
    }

    func startSharedCookieSync() {
        sharedCookiePoller?.invalidate()
        sharedCookiePoller = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncSharedCookiesIntoRenderer()
                await self?.persistRendererCookiesToSharedJar()
            }
        }
    }

    func stopSharedCookieSync() {
        sharedCookiePoller?.invalidate()
        sharedCookiePoller = nil
    }

    func mark3DInspectorInactive(notify: Bool) {
        isIn3DInspector = false
        guard notify else { return }
        NotificationCenter.default.post(name: .snapshot3DExited, object: nil)
    }

    func exit3DInspectorIfNeeded(notify: Bool) async {
        guard isIn3DInspector else { return }
        try? await evaluateJS(Snapshot3DBridge.exitScript)
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
    case elementNotFound(String)
    case timeout
    case platformNotSupported(String)
}

func errorResponse(code: String, message: String) -> [String: Any] {
    ["success": false, "error": ["code": code, "message": message]]
}

func successResponse(_ data: [String: Any] = [:]) -> [String: Any] {
    var result: [String: Any] = ["success": true]
    for (key, value) in data { result[key] = value }
    return result
}
