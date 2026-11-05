import AppKit

/// An immutable native renderer/tab grant is shared by actions and frame sampling.
@MainActor
final class ScriptWorkflowTab {
    typealias Body = [String: Any]
    struct Viewport: Equatable {
        let bounds: CGSize
        let layout: CGSize
        let visible: CGRect
        let scale: CGFloat
        let pixelRatio: CGFloat
        var metadata: Body { ["width": layout.width, "height": layout.height] }
        func displayPoint(_ css: CGPoint) -> CGPoint {
            CGPoint(x: (css.x - visible.minX) * bounds.width / visible.width,
                    y: (css.y - visible.minY) * bounds.height / visible.height)
        }
    }

    let id: String
    let renderer: any RendererEngine
    let view: NSView
    let router: Router
    let grant: ScriptRequestOwner
    let playback: ScriptPlaybackState
    let started = ProcessInfo.processInfo.systemUptime
    private let context: HandlerContext
    private let chromium: Bool
    private let key = "__kelpie_mac_workflow_" + UUID().uuidString

    init(context: HandlerContext, router: Router, grant: ScriptRequestOwner, playback: ScriptPlaybackState, id: String) throws {
        self.id = id
        self.context = context
        self.router = router
        self.grant = grant
        self.playback = playback
        chromium = context.activeEngineIsChromium
        if chromium {
            guard id == "chromium", let active = context.renderer else { throw ScriptWorkflowFailure("TAB_NOT_FOUND") }
            renderer = active
        } else {
            guard context.renderer == nil || context.renderer is WKWebViewRenderer else { throw ScriptWorkflowFailure("SCRIPT_RENDERER_UNSUPPORTED") }
            renderer = try context.resolveRenderer(tabId: id == "external" ? nil : id)
            if id == "external", context.tabStore(windowId: nil, tabId: nil) != nil { throw ScriptWorkflowFailure("TAB_NOT_ACTIVE") }
        }
        view = renderer.makeView()
        try requireCurrent()
    }

    var document: String { ConnectDocument.version(renderer) }
    var isAborted: Bool { Task.isCancelled || playback.isAbortRequested() }

    func requireCurrent() throws {
        guard context.activeEngineIsChromium == chromium else { throw ScriptWorkflowFailure("RENDERER_CHANGED") }
        let current = try context.resolveRenderer(tabId: id == "external" ? nil : id)
        guard current === renderer else { throw ScriptWorkflowFailure("TAB_CHANGED") }
        if !chromium, id != "external" {
            guard let uuid = UUID(uuidString: id),
                  let entry = WindowRegistry.shared.entry(containingTabId: uuid),
                  entry.tabStore.activeTab?.id == uuid else { throw ScriptWorkflowFailure("TAB_NOT_ACTIVE") }
        }
    }

    func check() async throws {
        guard !isAborted else { throw ScriptWorkflowFailure("SCRIPT_ABORTED") }
        guard await grant.isCurrent() else { throw ScriptWorkflowFailure("AUTHORIZATION_REVOKED") }
        guard !isAborted else { throw ScriptWorkflowFailure("SCRIPT_ABORTED") }
        guard ProcessInfo.processInfo.systemUptime - started < 300 else { throw ScriptWorkflowFailure("TIMEOUT") }
        try requireCurrent()
        guard view.window?.isVisible == true, !view.isHiddenOrHasHiddenAncestor else { throw ScriptWorkflowFailure("TAB_NOT_VISIBLE") }
    }

    func waitForLayout() async throws {
        let end = ProcessInfo.processInfo.systemUptime + 2
        var previous = CGRect.null
        var stable = ProcessInfo.processInfo.systemUptime
        repeat {
            try await check()
            view.window?.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            let rect = renderer.scriptViewportRect
            let now = ProcessInfo.processInfo.systemUptime
            if rect == previous, rect.width > 0, rect.height > 0 {
                if now - stable >= 0.08 { return }
            } else { previous = rect; stable = now }
            try await Task.sleep(nanoseconds: 16_000_000)
        } while ProcessInfo.processInfo.systemUptime < end
        throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE")
    }

    func fixed(_ expression: String, mutates: Bool = false) async throws -> Any? {
        try await check()
        guard !ScriptRendererDeadline.isRetiring(renderer) else { throw ScriptWorkflowFailure("BUSY") }
        if mutates {
            guard router.browserLease.begin() else { throw ScriptWorkflowFailure("BUSY") }
            router.invalidateAllBrowserReferences()
        }
        defer { if mutates { router.browserLease.end() } }
        let before = document
        let value: Any?
        do {
            value = try await ScriptRendererDeadline.run(
                renderer: renderer,
                mutates: mutates,
                lease: router.browserLease,
                cancelled: { self.isAborted },
                operation: { [self] in
                    try await check()
                    guard before == document else { throw ScriptWorkflowFailure("DOCUMENT_CHANGED") }
                    return try await renderer.evaluateBrowserControlJS(expression)
                }
            )
        } catch let failure as ScriptWorkflowFailure { throw failure } catch { throw ScriptWorkflowFailure("WEBVIEW_ERROR", mayHaveCompleted: mutates) }
        do { try await check() } catch { throw ScriptWorkflowFailure("INPUT_INTERRUPTED", mayHaveCompleted: mutates) }
        guard before == document else { throw ScriptWorkflowFailure("DOCUMENT_CHANGED", mayHaveCompleted: mutates) }
        return value
    }

    func viewport() async throws -> Viewport {
        guard let values = try await fixed("""
        (()=>{const v=globalThis.visualViewport;return [innerWidth,innerHeight,
        v?.offsetLeft??0,v?.offsetTop??0,v?.width??innerWidth,v?.height??innerHeight,
        v?.scale??1,devicePixelRatio]})()
        """) as? [NSNumber], values.count == 8 else { throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_UNAVAILABLE") }
        let parts = values.map { CGFloat($0.doubleValue) }
        let bounds = renderer.scriptViewportRect.size
        guard parts.allSatisfy({ $0.isFinite }), parts[0] > 0, parts[1] > 0, parts[4] > 0, parts[5] > 0,
              parts[6] > 0, parts[7] > 0, bounds.width > 0, bounds.height > 0 else { throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_UNAVAILABLE") }
        return Viewport(
            bounds: bounds,
            layout: CGSize(width: parts[0], height: parts[1]),
            visible: CGRect(x: parts[2], y: parts[3], width: parts[4], height: parts[5]),
            scale: parts[6],
            pixelRatio: parts[7]
        )
    }

    func target(_ target: Body, token: String? = nil, observe: Bool = false, dispatch: Bool = false, edit: Body? = nil) async throws -> Body {
        var options: Body = ["key": key, "target": target, "dispatch": dispatch]
        if let token { options["token"] = token }
        if observe { options["observe"] = true }
        if let edit { options["edit"] = edit }
        guard let input = ScriptBoundWorkflow.json(options),
              let pointer = kelpie_browser_script_target_expression(input) else { throw ScriptWorkflowFailure("INVALID_TARGET") }
        defer { kelpie_mcp_free_string(pointer) }
        guard let expression = ScriptBoundWorkflow.decode(String(cString: pointer))?["expression"] as? String else {
            throw ScriptWorkflowFailure("INVALID_TARGET")
        }
        guard let result = try await fixed(expression, mutates: dispatch || edit != nil) as? Body else {
            throw ScriptWorkflowFailure("TARGET_FAILED", mayHaveCompleted: dispatch || edit != nil)
        }
        return result
    }

    func documentIdentity() async throws -> String {
        guard let value = try await fixed("""
        (()=>{const key='\(key)_document';let state=globalThis[key];
        if(!state||state.document!==document){const bytes=new Uint32Array(4);crypto.getRandomValues(bytes);
        state={document,id:Array.from(bytes,v=>v.toString(16).padStart(8,'0')).join('')};globalThis[key]=state}
        return state.id})()
        """) as? String, value.count == 32 else { throw ScriptWorkflowFailure("CAPTURE_DOCUMENT_UNAVAILABLE") }
        return value
    }

    func output(_ source: String) async throws -> String {
        let expression: String
        switch source {
        case "url": expression = "location.href"
        case "title": expression = "document.title"
        case "status": expression = "document.readyState"
        default: throw ScriptWorkflowFailure("INVALID_OUTPUT")
        }
        guard let value = try await fixed("(()=>{const v=\(expression);return v.length<=16384?v:null})()") as? String else {
            throw ScriptWorkflowFailure("OUTPUT_BUDGET_EXCEEDED")
        }
        return value
    }

    func navigate(_ url: String) async throws {
        try await check()
        guard router.browserLease.begin() else { throw ScriptWorkflowFailure("BUSY") }
        defer { router.browserLease.end() }
        router.invalidateAllBrowserReferences()
        let response = try await ScriptRendererDeadline.run(
            renderer: renderer,
            seconds: 12,
            mutates: true,
            lease: router.browserLease,
            cancelled: { self.isAborted },
            operation: { [self] in
            try await check()
                return await router.handle(method: "navigate", body: ["url": url, "tabId": id], bypassRecordingGate: true, browserGatewayDispatch: true).json
            }
        )
        guard response["success"] as? Bool == true else { throw ScriptWorkflowFailure("NAVIGATION_FAILED", mayHaveCompleted: true) }
        try await check()
    }

    func scroll(_ body: Body) async throws {
        guard let x = body["deltaX"] as? NSNumber, let y = body["deltaY"] as? NSNumber,
              let args = ScriptBoundWorkflow.json(["x": x, "y": y]) else { throw ScriptWorkflowFailure("INVALID_SCRIPT") }
        _ = try await fixed("(p=>{scrollBy(p.x,p.y);return true})(\(args))", mutates: true)
    }

    func snapshot(maximumPixels: CGSize, viewport: Viewport) async throws -> NSImage {
        try await check()
        return try await ScriptRendererDeadline.run(
            renderer: renderer,
            seconds: 10,
            lease: router.browserLease,
            cancelled: { self.isAborted },
            operation: { [self] in
            try await check()
            return try await renderer.takeScriptSnapshot(viewport: viewport.visible, maximumPixels: maximumPixels, pixelRatio: viewport.pixelRatio)
            }
        )
    }

    func resetTargets() async {
        _ = try? await ScriptRendererDeadline.run(renderer: renderer, seconds: 2, lease: router.browserLease) { [self] in
            try await renderer.evaluateBrowserControlJS("delete globalThis['\(key)'];delete globalThis['\(key)_document']")
        }
    }
}
