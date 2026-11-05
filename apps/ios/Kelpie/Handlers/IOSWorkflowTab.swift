import WebKit

/// The visible WKWebView and tab identity stay pinned for the entire workflow.
@MainActor
final class IOSWorkflowTab {
    typealias Body = [String: Any]
    struct Viewport: Equatable {
        let bounds: CGSize
        let layout: CGSize
        let visible: CGRect
        let scale: CGFloat
        let pixelRatio: CGFloat
        let content: CGRect

        init(bounds: CGSize, layout: CGSize, visible: CGRect, scale: CGFloat, pixelRatio: CGFloat, content: CGRect? = nil) {
            self.bounds = bounds
            self.layout = layout
            self.visible = visible
            self.scale = scale
            self.pixelRatio = pixelRatio
            self.content = content ?? CGRect(origin: .zero, size: bounds)
        }

        var metadata: Body { ["width": layout.width, "height": layout.height] }
        var pointsPerCSSX: CGFloat { content.width / visible.width }

        func displayPoint(_ css: CGPoint) -> CGPoint {
            CGPoint(x: content.minX + (css.x - visible.minX) * pointsPerCSSX,
                    y: content.minY + (css.y - visible.minY) * content.height / visible.height)
        }
    }

    let id: String
    let view: WKWebView
    private let context: HandlerContext
    private let router: Router
    private let grant: IOSScriptGrant
    private let playback: ScriptPlaybackState
    private let key = "__kelpie_ios_workflow_" + UUID().uuidString

    init(context: HandlerContext, router: Router, grant: IOSScriptGrant, playback: ScriptPlaybackState, id: String) throws {
        self.id = id
        self.context = context
        self.router = router
        self.grant = grant
        self.playback = playback
        if let store = context.tabStore, let tab = store.activeBrowserTab, tab.id.uuidString == id {
            view = tab.webView
        } else if context.tabStore == nil, id == "external", let current = context.webView {
            view = current
        } else {
            throw IOSWorkflowFailure("TAB_NOT_ACTIVE")
        }
    }

    // Provisional navigation retires interaction tokens. Commit separately retires old pixels.
    private static let commits = NSMapTable<WKWebView, NSString>.weakToStrongObjects()
    static func documentCommitted(_ view: WKWebView) {
        commits.setObject(UUID().uuidString as NSString, forKey: view)
    }

    var document: String { ConnectDocument.version(view) + ":" + (Self.commits.object(forKey: view) as String? ?? "initial") }

    func waitForRecordingLayout(check: () async throws -> Void) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var last = CGRect.null
        var parent: UIView?
        var stableSince = ProcessInfo.processInfo.systemUptime
        repeat {
            try await check()
            view.window?.layoutIfNeeded()
            let frame = view.convert(view.bounds, to: view.window)
            let now = ProcessInfo.processInfo.systemUptime
            if !frame.isEmpty, let current = view.superview, last == frame, current === parent {
                if now - stableSince >= 0.08 { return }
            } else {
                last = frame
                parent = view.superview
                stableSince = now
            }
            try await Task.sleep(nanoseconds: 16_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE")
    }

    func requireCurrent() throws {
        if let store = context.tabStore {
            guard let tab = store.activeBrowserTab, tab.id.uuidString == id, tab.webView === view else {
                throw IOSWorkflowFailure("TAB_CHANGED")
            }
        } else if id != "external" || context.webView !== view {
            throw IOSWorkflowFailure("TAB_CHANGED")
        }
    }

    func focusForEditing() throws {
        try requireCurrent()
        let accepted = view.window != nil && view.becomeFirstResponder()
        #if DEBUG
        IOSFrameSampler.diagnostic(accepted ? "responder-accepted" : "responder-refused")
        #endif
        guard accepted else { throw IOSWorkflowFailure("INPUT_NOT_AVAILABLE") }
    }

    #if DEBUG
    var rendererContainsFirstResponder: Bool {
        func containsResponder(_ current: UIView) -> Bool {
            current.isFirstResponder || current.subviews.contains(where: containsResponder)
        }
        return containsResponder(view)
    }
    #endif

    private func requireMutationAuthority() async throws {
        guard await grant.isCurrent() else { throw IOSWorkflowFailure("AUTHORIZATION_REVOKED") }
        guard !Task.isCancelled, !playback.isAbortRequested() else { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
        try requireCurrent()
        guard view.window?.windowScene?.activationState == .foregroundActive else { throw IOSWorkflowFailure("TAB_NOT_VISIBLE") }
    }

    private func fixed(
        _ expression: String,
        mutates: Bool = false,
        consume: (@MainActor (Any?) -> Void)? = nil,
        missingResult: (@MainActor () -> Void)? = nil
    ) async throws -> Any? {
        try requireCurrent()
        if mutates {
            guard router.browserLease.begin() else { throw IOSWorkflowFailure("BUSY") }
            router.invalidateAllBrowserReferences()
        }
        defer { if mutates { router.browserLease.end() } }
        let before = document
        let value: Any?
        var evaluationStarted = false
        var resultReceived = false
        do {
            value = try await IOSRendererDeadline.run(view: view, mutates: mutates, lease: mutates ? router.browserLease : nil) { [self] in
                if mutates { try await requireMutationAuthority() }
                try requireCurrent()
                guard before == document else { throw IOSWorkflowFailure("DOCUMENT_CHANGED") }
                evaluationStarted = true
                do {
                    let result = try await BrowserControlWebKit.evaluate(expression, in: view)
                    resultReceived = true
                    // Consume privacy metadata before guards and even after the caller's deadline.
                    consume?(result)
                    return result
                } catch {
                    missingResult?()
                    throw error
                }
            }
        } catch {
            if evaluationStarted, !resultReceived { missingResult?() }
            throw error as? IOSWorkflowFailure ?? IOSWorkflowFailure("WEBVIEW_ERROR", mayHaveCompleted: mutates)
        }
        do { try requireCurrent() } catch { throw IOSWorkflowFailure("TAB_CHANGED", mayHaveCompleted: mutates) }
        guard before == document else { throw IOSWorkflowFailure("DOCUMENT_CHANGED", mayHaveCompleted: mutates) }
        return value
    }

    func viewport() async throws -> Viewport {
        let result = try await fixed("""
        (()=>{const v=globalThis.visualViewport;return [innerWidth,innerHeight,
        v?.offsetLeft??0,v?.offsetTop??0,v?.width??innerWidth,v?.height??innerHeight,
        v?.scale??1,devicePixelRatio]})()
        """)
        guard let values = result as? [NSNumber], values.count == 8 else {
            throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNAVAILABLE")
        }
        let parts = values.map { CGFloat($0.doubleValue) }
        guard parts.allSatisfy({ $0.isFinite }), parts[0] > 0, parts[1] > 0,
              parts[4] > 0, parts[5] > 0, view.bounds.width > 0, view.bounds.height > 0 else {
            throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNAVAILABLE")
        }
        let native = view.bounds.size
        let insets = view.scrollView.adjustedContentInset
        let insetValues = [insets.top, insets.bottom, insets.left, insets.right]
        guard insetValues.allSatisfy({ $0.isFinite && $0 >= 0 }), insets.left + insets.right < native.width,
              insets.top + insets.bottom < native.height else { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNAVAILABLE") }
        let content = CGRect(
            x: insets.left,
            y: insets.top,
            width: native.width - insets.left - insets.right,
            height: native.height - insets.top - insets.bottom
        )
        return Viewport(
            bounds: native,
            layout: CGSize(width: parts[0], height: parts[1]),
            visible: CGRect(x: parts[2], y: parts[3], width: parts[4], height: parts[5]),
            scale: parts[6],
            pixelRatio: parts[7],
            content: content
        )
    }

    func target(
        _ target: Body,
        token: String? = nil,
        observe: Bool = false,
        dispatch: Bool = false,
        edit: Body? = nil,
        postMutation: Bool = false,
        acceptFinalAcknowledgement: Bool = false,
        unknownOnFinalNavigation: Bool = true,
        validateMutationAcknowledgement: Bool = false,
        refuseSensitive: Bool = false,
        consume: (@MainActor (Body) -> Void)? = nil,
        missingResult: (@MainActor () -> Void)? = nil
    ) async throws -> Body {
        var options: Body = ["key": key, "target": target, "dispatch": dispatch]
        if let token { options["token"] = token }
        if observe { options["observe"] = true }
        if let edit { options["edit"] = edit }
        if postMutation { options["postMutation"] = true }
        if refuseSensitive { options["policy"] = ["refuseSensitive": true] }
        guard let input = IOSBoundWorkflow.json(options),
              let pointer = kelpie_browser_script_target_expression(input) else { throw IOSWorkflowFailure("INVALID_TARGET") }
        defer { kelpie_mcp_free_string(pointer) }
        guard let expression = IOSBoundWorkflow.decode(String(cString: pointer))?["expression"] as? String else {
            throw IOSWorkflowFailure("INVALID_TARGET")
        }
        var acknowledgement: Body?
        let value: Any?
        do {
            value = try await fixed(
                expression,
                mutates: dispatch || edit != nil,
                consume: { result in
                    acknowledgement = IOSPacedTypingExecutor.consumeCallback(
                        result,
                        token: token,
                        validateMutation: validateMutationAcknowledgement,
                        consume: consume,
                        missing: missingResult
                    )
                },
                missingResult: missingResult
            )
        } catch let failure as IOSWorkflowFailure {
            guard acceptFinalAcknowledgement, failure.code == "DOCUMENT_CHANGED", let acknowledgement else { throw failure }
            if unknownOnFinalNavigation || !IOSPacedTypingExecutor.hasKnownSensitivity(acknowledgement) { missingResult?() }
            return acknowledgement
        }
        guard let result = value as? Body, IOSPacedTypingExecutor.jsonBoolean(result["sensitive"]) != nil else {
            throw IOSWorkflowFailure("TARGET_FAILED", mayHaveCompleted: dispatch || edit != nil)
        }
        return result
    }

    func resetTargets() async {
        // The key contains only our UUID. Clear this view's isolated-world registry.
        _ = try? await IOSRendererDeadline.run(view: view, seconds: 2) { [self] in
            try await BrowserControlWebKit.evaluate("delete globalThis['\(key)']", in: view)
        }
    }

    func output(_ source: String) async throws -> String {
        let expression: String
        switch source {
        case "url": expression = "location.href"
        case "title": expression = "document.title"
        case "status": expression = "document.readyState"
        default: throw IOSWorkflowFailure("INVALID_OUTPUT")
        }
        guard let value = try await fixed("(()=>{const v=\(expression);return v.length<=16384?v:null})()") as? String else {
            throw IOSWorkflowFailure("OUTPUT_BUDGET_EXCEEDED")
        }
        return value
    }

    func scroll(_ body: Body) async throws {
        guard let x = body["deltaX"] as? NSNumber, let y = body["deltaY"] as? NSNumber,
              let args = IOSBoundWorkflow.json(["x": x, "y": y]) else { throw IOSWorkflowFailure("INVALID_SCRIPT") }
        _ = try await fixed("(p=>{scrollBy(p.x,p.y);return true})(\(args))", mutates: true)
    }

    func navigate(_ value: String, check: () async throws -> Void) async throws {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw IOSWorkflowFailure("INVALID_URL")
        }
        try requireCurrent()
        guard router.browserLease.begin() else { throw IOSWorkflowFailure("BUSY") }
        defer { router.browserLease.end() }
        router.invalidateAllBrowserReferences()
        let end = ContinuousClock.now.advanced(by: .seconds(10))
        let navigationLease = try await IOSWorkflowNavigation.issue(
            on: view,
            deadline: end,
            authorize: {
                try await check()
                try await self.requireMutationAuthority()
            },
            isLoading: { self.view.isLoading },
            load: {
                self.context.lastNavigationError = nil
                return self.view.load(URLRequest(url: url))
            }
        )
        defer { ConnectDocument.reserve(view, lease: nil) }
        repeat {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let version = ConnectDocument.version(view)
            guard navigationLease.allowsWait(version: version, authorized: true) else {
                #if DEBUG
                print("[WorkflowNavigationLease] wait-refused=" + navigationLease.debugState)
                #endif
                throw IOSWorkflowFailure("NAVIGATION_REPLACED", mayHaveCompleted: true)
            }
            do { try await check(); try requireCurrent() } catch {
                view.stopLoading()
                throw IOSWorkflowFailure("NAVIGATION_INTERRUPTED", mayHaveCompleted: true)
            }
            if context.lastNavigationError != nil { throw IOSWorkflowFailure("NAVIGATION_FAILED", mayHaveCompleted: true) }
            if navigationLease.allowsRead(version: version, loading: view.isLoading, authorized: true) { return }
        } while ContinuousClock.now < end
        #if DEBUG
        print("[WorkflowNavigationLease] timeout=" + navigationLease.debugState)
        #endif
        if navigationLease.allowsWait(version: ConnectDocument.version(view), authorized: true) { view.stopLoading() }
        throw IOSWorkflowFailure("TIMEOUT", mayHaveCompleted: true)
    }
}
