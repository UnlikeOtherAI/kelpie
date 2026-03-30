import AppKit

/// Chromium-based renderer conforming to RendererEngine.
/// Wraps CEFBridge (Obj-C++) and bridges callbacks to async/await.
@MainActor
final class CEFRenderer: RendererEngine {
    let engineName = "chromium"

    private let bridge: CEFBridge
    private let containerView: NSView

    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""
    private(set) var isLoading: Bool = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0.0

    var onStateChange: (() -> Void)?
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)?

    init() {
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        bridge = CEFBridge(parentView: containerView, url: "about:blank", identifier: "main")

        bridge.onStateChange = { [weak self] in
            Task { @MainActor in
                self?.syncState()
            }
        }

        bridge.onConsoleMessage = { [weak self] message in
            Task { @MainActor in
                self?.onScriptMessage?("mollotovConsole", message as? [String: Any] ?? [:])
            }
        }
    }

    private func syncState() {
        currentURL = URL(string: bridge.currentURL())
        currentTitle = bridge.currentTitle()
        isLoading = bridge.isLoading()
        canGoBack = bridge.canGoBack()
        canGoForward = bridge.canGoForward()
        onStateChange?()
    }

    // MARK: - RendererEngine

    func makeView() -> NSView { containerView }

    func load(url: URL) {
        bridge.loadURL(url.absoluteString)
    }

    func goBack() { bridge.goBack() }
    func goForward() { bridge.goForward() }
    func reload() { bridge.reload() }

    func evaluateJS(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            bridge.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let jsonString = result {
                    // CEF returns results as JSON strings — try to parse
                    if let data = jsonString.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) {
                        continuation.resume(returning: parsed)
                    } else {
                        continuation.resume(returning: jsonString)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            bridge.getAllCookies { cookieDicts in
                let cookies = (cookieDicts ?? []).compactMap { dict -> HTTPCookie? in
                    guard let dict = dict as? [String: Any],
                          let name = dict["name"] as? String,
                          let value = dict["value"] as? String,
                          let domain = dict["domain"] as? String,
                          let path = dict["path"] as? String else { return nil }

                    var props: [HTTPCookiePropertyKey: Any] = [
                        .name: name,
                        .value: value,
                        .domain: domain,
                        .path: path,
                    ]
                    if let httpOnly = dict["httpOnly"] as? Bool, httpOnly {
                        props[.init("HttpOnly")] = "TRUE"
                    }
                    if let secure = dict["secure"] as? Bool, secure {
                        props[.secure] = "TRUE"
                    }
                    if let expires = dict["expires"] as? Date {
                        props[.expires] = expires
                    }
                    return HTTPCookie(properties: props)
                }
                continuation.resume(returning: cookies)
            }
        }
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        await withTaskGroup(of: Void.self) { group in
            for cookie in cookies {
                group.addTask { @MainActor in
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        self.bridge.setCookieName(
                            cookie.name,
                            value: cookie.value,
                            domain: cookie.domain,
                            path: cookie.path,
                            httpOnly: cookie.isHTTPOnly,
                            secure: cookie.isSecure,
                            expires: cookie.expiresDate
                        ) { _ in
                            cont.resume()
                        }
                    }
                }
            }
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        // CEF only supports bulk delete — delete all then re-add others
        // For single cookie delete, use JS: document.cookie = "name=; expires=..."
        let js = "document.cookie = '\(cookie.name)=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=\(cookie.path); domain=\(cookie.domain)';"
        _ = try? await evaluateJS(js)
    }

    func deleteAllCookies() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            bridge.deleteAllCookies { _ in
                cont.resume()
            }
        }
    }

    func takeSnapshot() async throws -> NSImage {
        guard let data = await withCheckedContinuation({ (cont: CheckedContinuation<Data?, Never>) in
            bridge.takeScreenshot { pngData in
                cont.resume(returning: pngData as Data?)
            }
        }) else {
            throw HandlerError.noWebView
        }
        guard let image = NSImage(data: data) else {
            throw HandlerError.noWebView
        }
        return image
    }
}
