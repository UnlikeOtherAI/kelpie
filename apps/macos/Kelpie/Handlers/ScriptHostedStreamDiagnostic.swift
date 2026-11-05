#if DEBUG && KELPIE_HOSTED_STREAM_TEST
import AppKit

/// Hosted synthetic-fixture diagnostic only; the product capture path never consumes this stream.
@MainActor
final class ScriptHostedStreamDiagnostic {
    private let tab: ScriptWorkflowTab
    private let renderer: CEFRenderer
    private let bridge: CEFBridge
    private let window: NSWindow
    private let document: String
    private let geometry: ScriptMarkerGeometry
    private let viewport: ScriptCaptureViewport
    private let documentID: String
    private let fixtureOrigin: String
    private var probe: CEFHostedStreamProbe?

    static var requested: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["GITHUB_ACTIONS"] == "true" && env["RUNNER_OS"] == "macOS" &&
            env["KELPIE_HOSTED_RUNTIME"] == "1" && env["KELPIE_CEF_STREAM_TEST"] == "1"
    }

    init(tab: ScriptWorkflowTab) async throws {
        try await tab.check()
        guard let origin = ProcessInfo.processInfo.environment["KELPIE_CEF_STREAM_ORIGIN"],
              let parts = URLComponents(string: origin), parts.scheme == "http", parts.host == "127.0.0.1",
              let port = parts.port, (1...65535).contains(port), parts.user == nil, parts.password == nil,
              parts.path.isEmpty, parts.query == nil, parts.fragment == nil,
              origin == "http://127.0.0.1:\(port)" else { throw ScriptWorkflowFailure("INVALID_PARAM") }
        guard let renderer = tab.renderer as? CEFRenderer, let bridge = renderer.bridge,
              let window = tab.view.window else { throw ScriptWorkflowFailure("SCRIPT_RENDERER_UNSUPPORTED") }
        let state = try await tab.hostedFixtureCaptureState(origin: origin)
        try await tab.check()
        guard state.viewport.scale == 1, state.viewport.pageOrigin == .zero,
              state.viewport.visible.origin == .zero else { throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_UNAVAILABLE") }
        self.tab = tab
        self.renderer = renderer
        self.bridge = bridge
        self.window = window
        self.document = tab.document
        self.geometry = ScriptMarkerGeometry(tab: tab, window: window)
        self.viewport = state.viewport
        self.documentID = state.document
        self.fixtureOrigin = origin
    }

    private func isCurrent() -> Bool {
        guard !tab.isAborted, tab.renderer === renderer, renderer.bridge === bridge,
              tab.view === renderer.makeView(), tab.view.window === window, window.isVisible,
              !tab.view.isHiddenOrHasHiddenAncestor, tab.document == document,
              (try? tab.requireCurrent()) != nil else { return false }
        return ScriptMarkerGeometry(tab: tab, window: window) == geometry
    }

    func start() async throws {
        try await tab.check()
        guard isCurrent() else { throw ScriptWorkflowFailure("CAPTURE_DOCUMENT_CHANGED") }
        let probe = CEFHostedStreamProbe(
            bridge: bridge,
            epoch: UInt64.random(in: 1...UInt64.max),
            width: Double(viewport.bounds.width),
            height: Double(viewport.bounds.height),
            identity: { [weak self] in
                MainActor.assumeIsolated { self?.isCurrent() == true }
            }
        )
        self.probe = probe
        do {
            let started = try await ScriptRendererDeadline.run(
                renderer: renderer,
                lease: tab.router.browserLease,
                cancelled: { self.tab.isAborted },
                operation: {
                    await withCheckedContinuation { continuation in
                        probe.start { continuation.resume(returning: $0) }
                    }
                }
            )
            guard started else { throw ScriptWorkflowFailure("CAPTURE_FAILED") }
            print("[WorkflowHostedStream] event=started")
        } catch {
            Task { _ = await probe.stop() }
            throw error
        }
    }

    /// Stops and joins CEF work first; only a current final grant and coherent state can expose numbers.
    func finish(allowed: Bool) async {
        guard let probe else { return }
        defer { self.probe = nil }
        do {
            let stopped = try await ScriptRendererDeadline.run(
                renderer: renderer,
                seconds: 8,
                lease: tab.router.browserLease,
                cancelled: { self.tab.isAborted },
                operation: {
                    await withCheckedContinuation { continuation in
                        probe.stop { continuation.resume(returning: $0) }
                    }
                }
            )
            guard stopped, allowed else { print("[WorkflowHostedStream] event=discarded"); return }
            try await tab.check()
            let state = try await tab.hostedFixtureCaptureState(origin: fixtureOrigin)
            try await tab.check()
            guard isCurrent(), state.document == documentID, state.viewport == viewport,
                  let samples = probe.seal(afterAudit: true) as? [[String: NSNumber]], samples.count <= 64 else {
                print("[WorkflowHostedStream] event=discarded")
                return
            }
            var validated: [(receipt: Int, protocolTime: Int, x: Int, y: Int)] = []
            for sample in samples {
                guard let receipt = sample["receiptMs"]?.doubleValue, let protocolTime = sample["protocolMs"]?.doubleValue,
                      let x = sample["x"]?.intValue, let y = sample["y"]?.intValue,
                      receipt.isFinite, protocolTime.isFinite, receipt >= 0, receipt <= 5000,
                      protocolTime >= 0, protocolTime <= 5000, (0...1920).contains(x), (0...1920).contains(y) else {
                    print("[WorkflowHostedStream] event=discarded")
                    return
                }
                validated.append((Int(receipt), Int(protocolTime), x, y))
            }
            for (index, sample) in validated.enumerated() {
                print("[WorkflowHostedStream] event=sample index=\(index) receipt=\(sample.receipt) " +
                      "protocol=\(sample.protocolTime) x=\(sample.x) y=\(sample.y)")
            }
            print("[WorkflowHostedStream] event=complete count=\(samples.count)")
        } catch {
            Task { _ = await probe.stop() }
            print("[WorkflowHostedStream] event=discarded")
        }
    }
}
#endif
