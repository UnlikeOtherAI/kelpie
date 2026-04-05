# macOS Gecko (Firefox) Renderer Implementation Plan

> **Superseded** by `docs/plans/2026-04-01-macos-gecko-bundled.md`. The subprocess+CDP approach from this plan is retained but the binary is now bundled inside the app — no external Firefox.app required.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Firefox/Gecko as a third renderer option on macOS alongside WebKit and Chromium (CEF), using Firefox's Remote Protocol (CDP-compatible WebSocket) to control a Firefox subprocess.

**Architecture:** Spawn Firefox.app as a subprocess with `--remote-debugging-port <PORT>`, connect via WebSocket using Firefox's CDP-compatible Remote Protocol, and implement `RendererEngine` using CDP commands for navigation, JS eval, screenshots, and cookies. The `makeView()` returns a `GeckoLiveView` that auto-refreshes from `Page.captureScreenshot` at ~5fps to show actual Firefox rendering inside the Kelpie shell.

**Tech Stack:** Swift, URLSession WebSocket, Firefox Remote Protocol (CDP-compatible), Foundation Process, macOS 13+

---

## Background

The existing renderer abstraction (`RendererEngine` protocol in `Renderer/RendererEngine.swift`) is clean and simple. `WKWebViewRenderer` wraps WebKit; `CEFRenderer` wraps CEF via Obj-C++ bridging. For Gecko/Firefox, full `libxul` embedding is impractical — Mozilla's desktop embedding API is unmaintained. Instead, we use the same approach as Playwright: spawn Firefox with `--remote-debugging-port`, connect via WebSocket, and issue CDP commands.

Firefox CDP endpoint flow:
1. Spawn Firefox → `http://localhost:<PORT>/json/version` becomes available
2. Fetch WebSocket debugger URL from that endpoint
3. Connect WebSocket, send JSON-RPC commands (same shape as Chrome DevTools Protocol)
4. Listen to Page/Target events for navigation state

Key Firefox CDP commands used:
- `Page.enable` / `Network.enable` — activate event domains
- `Page.navigate` / `Page.reload` / `Page.goBack` / `Page.goForward`
- `Page.getNavigationHistory` — canGoBack / canGoForward state
- `Runtime.evaluate` — JS execution
- `Page.captureScreenshot` — base64 PNG for snapshot + live view
- `Network.getAllCookies` / `Network.setCookie` / `Network.deleteCookies`

Firefox must already be installed at one of the standard paths:
- `/Applications/Firefox.app/Contents/MacOS/firefox`
- `/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox`
- `~/Applications/Firefox.app/Contents/MacOS/firefox`

---

## Task 1: Add gecko case to RendererState

**Files:**
- Modify: `apps/macos/Kelpie/Renderer/RendererState.swift`

**Step 1: Open the file and add the `.gecko` case**

Current `Engine` enum has `.webkit` and `.chromium`. Add `.gecko`:

```swift
enum Engine: String, CaseIterable {
    case webkit = "webkit"
    case chromium = "chromium"
    case gecko = "gecko"

    var displayName: String {
        switch self {
        case .webkit: return "Safari (WebKit)"
        case .chromium: return "Chrome (Chromium)"
        case .gecko: return "Firefox (Gecko)"
        }
    }
}
```

**Step 2: Verify Xcode build succeeds**

Open Xcode → Product → Build (⌘B). Expect: build succeeds. The `RendererHandler` error message still says "webkit|chromium" — that's updated in Task 7.

**Step 3: Commit**

```bash
git add apps/macos/Kelpie/Renderer/RendererState.swift
git commit -m "feat(macos): add gecko case to RendererState.Engine"
```

---

## Task 2: Firefox process manager

**Files:**
- Create: `apps/macos/Kelpie/Renderer/GeckoProcessManager.swift`

**Overview:** Finds Firefox.app, spawns it with remote debugging flags on a free port, and manages the process lifecycle (start, stop, crash detection).

**Step 1: Create `GeckoProcessManager.swift`**

```swift
import Foundation

/// Manages a Firefox subprocess with the Remote Debugging Protocol enabled.
/// Finds Firefox.app at standard macOS install paths and spawns it with a
/// dedicated profile so it doesn't interfere with the user's own Firefox.
@MainActor
final class GeckoProcessManager {
    private(set) var debugPort: Int = 0
    private var process: Process?
    private var profileDir: URL?

    static let firefoxPaths: [String] = [
        "/Applications/Firefox.app/Contents/MacOS/firefox",
        "/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox",
        (NSHomeDirectory() as NSString).appendingPathComponent(
            "Applications/Firefox.app/Contents/MacOS/firefox"
        ),
    ]

    enum GeckoError: Error {
        case firefoxNotFound
        case portUnavailable
        case startupTimeout
    }

    /// Returns the path to the Firefox binary, or nil if not installed.
    static func locateFirefox() -> String? {
        firefoxPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Starts Firefox and waits until the CDP endpoint is reachable.
    /// Throws `GeckoError.firefoxNotFound` if Firefox is not installed.
    func start() async throws {
        guard let execPath = Self.locateFirefox() else {
            throw GeckoError.firefoxNotFound
        }

        let port = Self.findFreePort()
        guard port > 0 else { throw GeckoError.portUnavailable }
        debugPort = port

        // Isolated profile so Gecko doesn't touch the user's Firefox data
        let tempProfile = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.kelpie.gecko-profile-\(port)")
        try? FileManager.default.createDirectory(at: tempProfile, withIntermediateDirectories: true)
        profileDir = tempProfile

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: execPath)
        proc.arguments = [
            "--remote-debugging-port", "\(port)",
            "--no-remote",
            "--profile", tempProfile.path,
            "--headless",
            "about:blank",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        process = proc
        NSLog("[GeckoProcessManager] Firefox PID=%d port=%d", proc.processIdentifier, port)

        try await waitForEndpoint(port: port)
    }

    func stop() {
        process?.terminate()
        process = nil
        if let dir = profileDir {
            try? FileManager.default.removeItem(at: dir)
            profileDir = nil
        }
        debugPort = 0
    }

    var isRunning: Bool { process?.isRunning == true }

    // MARK: - Private

    private func waitForEndpoint(port: Int, retries: Int = 40) async throws {
        let url = URL(string: "http://localhost:\(port)/json/version")!
        for _ in 0..<retries {
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
            if let _ = try? await URLSession.shared.data(from: url) {
                return
            }
        }
        throw GeckoError.startupTimeout
    }

    private static func findFreePort() -> Int {
        let sock = socket(AF_INET6, SOCK_STREAM, 0)
        guard sock >= 0 else { return 0 }
        defer { close(sock) }
        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = 0
        addr.sin6_addr = in6addr_any
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        var result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard result == 0 else { return 0 }
        var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
        result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        guard result == 0 else { return 0 }
        return Int(addr.sin6_port.bigEndian)
    }
}
```

**Step 2: Verify build**

Build in Xcode (⌘B). Expected: no errors.

**Step 3: Commit**

```bash
git add apps/macos/Kelpie/Renderer/GeckoProcessManager.swift
git commit -m "feat(macos): add GeckoProcessManager for Firefox subprocess lifecycle"
```

---

## Task 3: CDP WebSocket client

**Files:**
- Create: `apps/macos/Kelpie/Renderer/GeckoCDPClient.swift`

**Overview:** A minimal CDP JSON-RPC client over `URLSessionWebSocketTask`. Sends commands (returns a `Sendable` result future keyed by ID), and delivers events to registered handlers.

**Step 1: Create `GeckoCDPClient.swift`**

```swift
import Foundation

/// Minimal CDP (Chrome DevTools Protocol) client over WebSocket.
/// Used to drive Firefox via its Remote Debugging Protocol.
@MainActor
final class GeckoCDPClient: NSObject, URLSessionWebSocketDelegate {
    typealias EventHandler = ([String: Any]) -> Void

    private var task: URLSessionWebSocketTask?
    private var nextId: Int = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var eventHandlers: [String: [EventHandler]] = [:]
    private var session: URLSession?

    enum CDPError: Error {
        case noConnection
        case commandFailed(String)
        case malformedResponse
    }

    // MARK: - Connection

    /// Connects to the Firefox CDP WebSocket endpoint on the given port.
    func connect(port: Int) async throws {
        let wsURL = try await resolveWebSocketURL(port: port)
        let config = URLSessionConfiguration.default
        let sess = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = sess
        let ws = sess.webSocketTask(with: wsURL)
        task = ws
        ws.resume()
        startReceiveLoop()
    }

    func disconnect() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        for (_, cont) in pending {
            cont.resume(throwing: CDPError.noConnection)
        }
        pending.removeAll()
    }

    // MARK: - Commands

    /// Sends a CDP command and returns the `result` dictionary.
    @discardableResult
    func send(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let task else { throw CDPError.noConnection }
        let id = nextId
        nextId += 1
        var message: [String: Any] = ["id": id, "method": method]
        if !params.isEmpty { message["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: message)
        let string = String(data: data, encoding: .utf8)!
        try await task.send(.string(string))
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
        }
    }

    // MARK: - Events

    /// Registers a handler for a CDP event method (e.g. "Page.loadEventFired").
    func on(_ method: String, handler: @escaping EventHandler) {
        eventHandlers[method, default: []].append(handler)
    }

    // MARK: - Private

    private func resolveWebSocketURL(port: Int) async throws -> URL {
        let url = URL(string: "http://localhost:\(port)/json/list")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let wsURL = first["webSocketDebuggerUrl"] as? String,
              let url = URL(string: wsURL) else {
            throw CDPError.malformedResponse
        }
        return url
    }

    private func startReceiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.handleMessage(message)
                    self.startReceiveLoop()
                }
            case .failure(let error):
                NSLog("[GeckoCDPClient] WebSocket error: %@", error.localizedDescription)
                Task { @MainActor in
                    for (_, cont) in self.pending {
                        cont.resume(throwing: error)
                    }
                    self.pending.removeAll()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let string: String
        switch message {
        case .string(let s): string = s
        case .data(let d): string = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let id = json["id"] as? Int, let cont = pending.removeValue(forKey: id) {
            if let error = json["error"] as? [String: Any],
               let msg = error["message"] as? String {
                cont.resume(throwing: CDPError.commandFailed(msg))
            } else {
                cont.resume(returning: json["result"] as? [String: Any] ?? [:])
            }
            return
        }
        if let method = json["method"] as? String,
           let params = json["params"] as? [String: Any] {
            eventHandlers[method]?.forEach { $0(params) }
        }
    }
}
```

**Step 2: Verify build**

Build in Xcode (⌘B). Expected: no errors.

**Step 3: Commit**

```bash
git add apps/macos/Kelpie/Renderer/GeckoCDPClient.swift
git commit -m "feat(macos): add GeckoCDPClient - CDP WebSocket client for Firefox"
```

---

## Task 4: GeckoLiveView — screenshot-driven NSView

**Files:**
- Create: `apps/macos/Kelpie/Renderer/GeckoLiveView.swift`

**Overview:** An `NSView` subclass that periodically fires a screenshot callback and renders the result using `CALayer`. Drives itself; the owner just sets `screenshotProvider` and calls `startRefreshing()`/`stopRefreshing()`.

**Step 1: Create `GeckoLiveView.swift`**

```swift
import AppKit

/// NSView that renders Firefox's current viewport by polling Page.captureScreenshot
/// at ~5fps. Displayed when Gecko is the active renderer.
@MainActor
final class GeckoLiveView: NSView {
    var screenshotProvider: (() async -> NSImage?)? = nil

    private var refreshTimer: Timer?
    private var imageLayer = CALayer()
    private var isRefreshing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.frame = bounds
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func startRefreshing() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
    }

    func stopRefreshing() {
        isRefreshing = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func tick() async {
        guard let image = await screenshotProvider?() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
    }
}
```

**Step 2: Verify build**

Build in Xcode (⌘B). Expected: no errors.

**Step 3: Commit**

```bash
git add apps/macos/Kelpie/Renderer/GeckoLiveView.swift
git commit -m "feat(macos): add GeckoLiveView - screenshot-driven NSView for Firefox rendering"
```

---

## Task 5: GeckoRenderer — core implementation

**Files:**
- Create: `apps/macos/Kelpie/Renderer/GeckoRenderer.swift`

**Overview:** Implements `RendererEngine` by combining `GeckoProcessManager`, `GeckoCDPClient`, and `GeckoLiveView`. On init, starts Firefox and connects CDP. All `RendererEngine` methods translate directly to CDP commands.

**Step 1: Create `GeckoRenderer.swift`**

```swift
import AppKit

/// Gecko/Firefox renderer conforming to RendererEngine.
/// Spawns a Firefox subprocess with --remote-debugging-port and drives it
/// via Firefox Remote Protocol (CDP-compatible WebSocket).
@MainActor
final class GeckoRenderer: RendererEngine {
    let engineName = "gecko"

    private let processManager = GeckoProcessManager()
    private let cdp = GeckoCDPClient()
    private let liveView: GeckoLiveView

    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""
    private(set) var isLoading: Bool = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0.0

    var onStateChange: (() -> Void)?
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)?

    init() {
        liveView = GeckoLiveView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        liveView.wantsLayer = true
        Task { @MainActor in
            await self.startFirefox()
        }
    }

    // MARK: - RendererEngine

    func makeView() -> NSView { liveView }

    func load(url: URL) {
        currentURL = url
        isLoading = true
        onStateChange?()
        Task { @MainActor in
            try? await cdp.send("Page.navigate", params: ["url": url.absoluteString])
        }
    }

    func goBack() {
        Task { @MainActor in
            try? await cdp.send("Page.goBack")
        }
    }

    func goForward() {
        Task { @MainActor in
            try? await cdp.send("Page.goForward")
        }
    }

    func reload() {
        isLoading = true
        onStateChange?()
        Task { @MainActor in
            try? await cdp.send("Page.reload")
        }
    }

    func evaluateJS(_ script: String) async throws -> Any? {
        let result = try await cdp.send("Runtime.evaluate", params: [
            "expression": script,
            "returnByValue": true,
            "awaitPromise": true,
        ])
        guard let resultObj = result["result"] as? [String: Any] else { return nil }
        if let exception = result["exceptionDetails"] as? [String: Any],
           let text = exception["text"] as? String {
            throw HandlerError.noWebView // surface as generic error; CDP exception text is in logs
        }
        return resultObj["value"]
    }

    func allCookies() async -> [HTTPCookie] {
        guard let result = try? await cdp.send("Network.getAllCookies"),
              let cookies = result["cookies"] as? [[String: Any]] else { return [] }
        return cookies.compactMap(makeCookie)
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            var params: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "secure": cookie.isSecure,
                "httpOnly": cookie.isHTTPOnly,
            ]
            if let expires = cookie.expiresDate {
                params["expires"] = expires.timeIntervalSince1970
            }
            try? await cdp.send("Network.setCookie", params: params)
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        try? await cdp.send("Network.deleteCookies", params: [
            "name": cookie.name,
            "domain": cookie.domain,
        ])
    }

    func deleteAllCookies() async {
        let all = await allCookies()
        for cookie in all {
            await deleteCookie(cookie)
        }
    }

    func takeSnapshot() async throws -> NSImage {
        let result = try await cdp.send("Page.captureScreenshot", params: ["format": "png"])
        guard let b64 = result["data"] as? String,
              let data = Data(base64Encoded: b64),
              let image = NSImage(data: data) else {
            throw HandlerError.noWebView
        }
        return image
    }

    // MARK: - Startup

    private func startFirefox() async {
        do {
            try await processManager.start()
            try await cdp.connect(port: processManager.debugPort)
            registerCDPEvents()
            liveView.screenshotProvider = { [weak self] in
                try? await self?.takeSnapshot()
            }
            liveView.startRefreshing()
            // Enable required CDP domains
            try await cdp.send("Page.enable")
            try await cdp.send("Network.enable")
            NSLog("[GeckoRenderer] Firefox started on port %d", processManager.debugPort)
        } catch {
            NSLog("[GeckoRenderer] startup failed: %@", error.localizedDescription)
        }
    }

    private func registerCDPEvents() {
        cdp.on("Page.frameNavigated") { [weak self] params in
            guard let self, let frame = params["frame"] as? [String: Any] else { return }
            if let urlStr = frame["url"] as? String { self.currentURL = URL(string: urlStr) }
            Task { @MainActor in
                await self.refreshNavHistory()
            }
            self.onStateChange?()
        }
        cdp.on("Page.loadEventFired") { [weak self] _ in
            self?.isLoading = false
            self?.estimatedProgress = 1.0
            self?.onStateChange?()
        }
        cdp.on("Page.domContentEventFired") { [weak self] _ in
            self?.estimatedProgress = 0.7
            self?.onStateChange?()
        }
    }

    private func refreshNavHistory() async {
        guard let result = try? await cdp.send("Page.getNavigationHistory"),
              let index = result["currentIndex"] as? Int,
              let entries = result["entries"] as? [[String: Any]] else { return }
        canGoBack = index > 0
        canGoForward = index < entries.count - 1
        if let entry = entries[safe: index] {
            currentTitle = entry["title"] as? String ?? ""
            if let urlStr = entry["url"] as? String { currentURL = URL(string: urlStr) }
        }
        onStateChange?()
    }

    // MARK: - Cookie mapping

    private func makeCookie(_ dict: [String: Any]) -> HTTPCookie? {
        guard let name = dict["name"] as? String,
              let value = dict["value"] as? String,
              let domain = dict["domain"] as? String else { return nil }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value,
            .domain: domain, .path: dict["path"] as? String ?? "/",
        ]
        if dict["secure"] as? Bool == true { props[.secure] = "TRUE" }
        if let exp = dict["expires"] as? Double, exp > 0 {
            props[.expires] = Date(timeIntervalSince1970: exp)
        }
        return HTTPCookie(properties: props)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

**Step 2: Verify build**

Build in Xcode (⌘B). Expected: no errors.

**Step 3: Commit**

```bash
git add apps/macos/Kelpie/Renderer/GeckoRenderer.swift
git commit -m "feat(macos): add GeckoRenderer - Firefox via CDP Remote Protocol"
```

---

## Task 6: Wire gecko into ServerState

**Files:**
- Modify: `apps/macos/Kelpie/Network/ServerState.swift`

**Step 1: Add geckoRenderer stored property**

After the existing `private(set) var cefRenderer: CEFRenderer?` line, add:

```swift
private(set) var geckoRenderer: GeckoRenderer?
```

**Step 2: Add gecko case to `renderer(for:)`**

The `renderer(for:)` switch currently handles `.webkit` and `.chromium`. Add:

```swift
case .gecko:
    if let geckoRenderer {
        return geckoRenderer
    }
    let renderer = GeckoRenderer()
    renderer.onScriptMessage = { [weak self] name, body in
        self?.handlerContext.handleScriptMessage(name: name, body: body)
    }
    geckoRenderer = renderer
    return renderer
```

**Step 3: Verify build**

Build in Xcode (⌘B). Expected: no errors.

**Step 4: Commit**

```bash
git add apps/macos/Kelpie/Network/ServerState.swift
git commit -m "feat(macos): wire GeckoRenderer into ServerState"
```

---

## Task 7: Update RendererHandler and CookieMigrator

**Files:**
- Modify: `apps/macos/Kelpie/Handlers/RendererHandler.swift`
- Modify: `apps/macos/Kelpie/Renderer/CookieMigrator.swift`

**Step 1: Update RendererHandler error message**

In `setRenderer(_:)`, the guard that checks for a valid engine name currently shows:

```swift
return errorResponse(code: "INVALID_PARAM", message: "engine must be webkit or chromium")
```

Change to:

```swift
return errorResponse(code: "INVALID_PARAM", message: "engine must be webkit, chromium, or gecko")
```

**Step 2: Update CookieMigrator**

`CookieMigrator.migrate` currently skips migration when source is `"chromium"` due to a CEF bridge crash. Gecko cookie export works fine via CDP. No change needed — the existing guard only skips `"chromium"`, Gecko will migrate correctly.

Verify the guard reads:

```swift
guard source.engineName != "chromium" else { return }
```

No change required; gecko → webkit and webkit → gecko migrations work.

**Step 3: Verify build**

Build in Xcode (⌘B). Expected: no errors.

**Step 4: Commit**

```bash
git add apps/macos/Kelpie/Handlers/RendererHandler.swift
git commit -m "feat(macos): update RendererHandler to accept gecko engine"
```

---

## Task 8: Manual verification

No automated test target exists for the macOS app. Verify manually:

**Step 1: Build and run**

In Xcode: Product → Run (⌘R). The app should start normally with the default WebKit renderer.

**Step 2: Verify Firefox is installed**

```bash
ls "/Applications/Firefox.app/Contents/MacOS/firefox"
```

If missing, install Firefox from mozilla.org before continuing.

**Step 3: Switch to Gecko via API**

```bash
curl -s -X POST http://localhost:8420/v1/set-renderer \
  -H "Content-Type: application/json" \
  -d '{"engine":"gecko"}' | python3 -m json.tool
```

Expected response:
```json
{ "success": true, "engine": "gecko", "changed": true }
```

**Step 4: Navigate and verify**

```bash
curl -s -X POST http://localhost:8420/v1/navigate \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}' | python3 -m json.tool

curl -s -X POST http://localhost:8420/v1/get-current-url | python3 -m json.tool
```

Expected: `currentUrl` contains `https://example.com`.

**Step 5: Verify live view refreshes**

In the macOS app window, you should see a dark background with the Firefox-rendered page appearing within ~1 second of navigation. The view should update at ~5fps.

**Step 6: Verify get-renderer reports gecko**

```bash
curl -s http://localhost:8420/v1/get-renderer | python3 -m json.tool
```

Expected:
```json
{
  "success": true,
  "engine": "gecko",
  "available": ["webkit", "chromium", "gecko"]
}
```

**Step 7: Switch back to WebKit**

```bash
curl -s -X POST http://localhost:8420/v1/set-renderer \
  -H "Content-Type: application/json" \
  -d '{"engine":"webkit"}' | python3 -m json.tool
```

Expected: `"changed": true`. The WebKit view should resume in the app shell.

**Step 8: Commit verification result**

If all checks pass, no code changes needed. If you hit a bug, fix it before this commit.

```bash
git add -p  # stage only intentional fixes
git commit -m "fix(macos): <describe any fix found during verification>"
```

---

## Task 9: Update docs

**Files:**
- Modify: `docs/browser-engines.md` — update macOS table
- Modify: `docs/functionality.md` — update renderer switching section
- Modify: `docs/api/browser.md` — update set-renderer/get-renderer accepted values

**Step 1: Update `docs/browser-engines.md` macOS table**

Find the macOS engine table and change the Gecko row status from `"Available but not embedded"` to `"Available — CDP subprocess"`:

```markdown
| **Gecko** | Available — CDP subprocess | Spawns Firefox.app with --remote-debugging-port; driven via Firefox Remote Protocol |
```

Update the "Current Implementation" sentence:

```markdown
**Current Implementation:** macOS apps support WebKit, CEF (Chromium), and Gecko (Firefox) with runtime switching via the renderer abstraction layer. Gecko uses a Firefox subprocess controlled via the CDP-compatible Remote Debugging Protocol.
```

**Step 2: Update `docs/api/browser.md` set-renderer section**

Find the `engine` parameter description and add `gecko`:

```
engine: "webkit" | "chromium" | "gecko"
```

**Step 3: Update `docs/functionality.md`**

Find the renderer switching section and add Gecko to the available engines list.

**Step 4: Commit**

```bash
git add docs/browser-engines.md docs/functionality.md docs/api/browser.md
git commit -m "docs: update engine docs for macOS Gecko renderer"
```

---

## Known Limitations (acceptable for first cut)

- **Headless only**: Firefox runs with `--headless`. The `GeckoLiveView` shows live screenshots (~200ms latency). A future iteration can explore `ScreenCaptureKit`-based window embedding for sub-frame latency.
- **Firefox must be pre-installed**: The app does not bundle Firefox. If absent, switching to gecko returns a startup error in the logs; the renderer state does not change. A future iteration should surface this as an HTTP error in `set-renderer`.
- **Cookie export on switch from Gecko**: Works via CDP `Network.getAllCookies`. Works for non-httpOnly cookies; httpOnly flags are preserved.
- **`canGoBack`/`canGoForward` latency**: Updated after `Page.frameNavigated`, not instantly on navigation call. Acceptable for LLM-driven use.
- **Script message bridge**: `onScriptMessage` is wired but no console/network bridge scripts are injected into Firefox yet. `get-console-messages` will return empty. A future iteration injects `Runtime.evaluate`-based polyfills via `Page.addScriptToEvaluateOnNewDocument`.
