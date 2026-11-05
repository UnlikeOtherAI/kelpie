import AppKit

/// Native geometry is captured before the recording chrome changes.
@MainActor
struct ScriptMarkerGeometry: Equatable {
    let viewport: CGRect
    let windowRect: CGRect
    let backingScale: CGFloat

    init(tab: ScriptWorkflowTab, window: NSWindow) {
        viewport = tab.renderer.scriptViewportRect
        windowRect = tab.view.convert(tab.view.bounds, to: nil)
        backingScale = window.backingScaleFactor
    }
}

/// Retains only the last marker; expiry never waits for an asynchronous authority check.
@MainActor
final class ScriptMarkerRetiree {
    private var presentation: ScriptPresentation?
    private var tab: ScriptWorkflowTab?
    private weak var window: NSWindow?
    private let document: String
    private let end: TimeInterval
    private let geometry: ScriptMarkerGeometry
    private var timer: Timer?
    private var authorityTask: Task<Void, Never>?

    init(
        presentation: ScriptPresentation,
        tab: ScriptWorkflowTab,
        window: NSWindow,
        end: TimeInterval,
        geometry: ScriptMarkerGeometry
    ) {
        self.presentation = presentation
        self.tab = tab
        self.window = window
        self.document = tab.document
        self.end = end
        self.geometry = geometry
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkLocal() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        authorityTask = Task { [weak self, grant = tab.grant] in
            while !Task.isCancelled {
                guard await grant.isCurrent() else { self?.stop(); return }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        checkLocal()
    }

    private func checkLocal() {
        guard presentation != nil else { return }
        guard ProcessInfo.processInfo.systemUptime < end, let window, let tab,
              tab.view.window === window, window.isVisible, window.isKeyWindow,
              !tab.view.isHiddenOrHasHiddenAncestor,
              tab.document == document, (try? tab.requireCurrent()) != nil,
              ScriptMarkerGeometry(tab: tab, window: window) == geometry else {
            stop()
            return
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        authorityTask?.cancel()
        authorityTask = nil
        presentation?.stop()
        presentation = nil
        tab = nil
    }
}
