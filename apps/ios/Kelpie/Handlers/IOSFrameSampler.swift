import UIKit
import WebKit

/// One in-flight WebKit viewport sample. Every accepted frame carries its request-time overlay and document stamp.
@MainActor
final class IOSFrameSampler {
    typealias Receiver = (CGImage, TimeInterval, Int?, String, IOSWorkflowTab.Viewport) throws -> Void
    private let tab: IOSWorkflowTab
    private let presentation: IOSWorkflowPresentation
    private let check: () async throws -> Void
    private let receive: Receiver
    private let continuous: Bool
    private let fps: Int
    private let maxWidth: Int
    private let duration: TimeInterval
    private let startTime: TimeInterval
    private var initial: IOSWorkflowTab.Viewport?
    private var initialDocument: String?
    private var busy = false
    private var stopping = false
    private var stepPending = false
    private var lastRequest: TimeInterval?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var ticker: Task<Void, Never>?
    private(set) var dropped = 0
    private(set) var failure: IOSWorkflowFailure?

    init(
        tab: IOSWorkflowTab,
        presentation: IOSWorkflowPresentation,
        settings: [String: Any],
        check: @escaping () async throws -> Void,
        receive: @escaping Receiver
    ) {
        self.tab = tab
        self.presentation = presentation
        self.check = check
        self.receive = receive
        continuous = (settings["formats"] as? [String] ?? []).contains { $0 == "gif" || $0 == "video" }
        fps = settings["fps"] as? Int ?? 15
        maxWidth = settings["maxWidth"] as? Int ?? 1280
        duration = Double(settings["maxDurationMs"] as? Int ?? 60000) / 1000
        startTime = ProcessInfo.processInfo.systemUptime
    }

    var elapsed: TimeInterval { min(duration, ProcessInfo.processInfo.systemUptime - startTime) }

    func start() async throws {
        guard continuous else { return }
        while !(try await sample(step: nil, document: nil)) { try checkTime() }
        ticker = Task { @MainActor [weak self] in await self?.periodic() }
    }

    func step(_ index: Int?, document: String? = nil, prepare: (() -> Void)? = nil) async throws {
        stepPending = true
        defer { stepPending = false }
        while busy { await withCheckedContinuation { waiters.append($0) } }
        if let failure { throw failure }
        guard !stopping else { throw IOSWorkflowFailure("CAPTURE_STOPPED") }
        if !continuous, index == nil { prepare?(); return }
        if continuous, let lastRequest {
            let delay = lastRequest + 1.0 / Double(fps) - ProcessInfo.processInfo.systemUptime
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        }
        while !(try await sample(step: index, document: document, prepare: prepare)) { try checkTime() }
    }

    func stop() async {
        stopping = true
        ticker?.cancel()
        await ticker?.value
        ticker = nil
    }

    private func periodic() async {
        let interval = 1.0 / Double(fps)
        var due = ProcessInfo.processInfo.systemUptime + interval
        while !stopping && !Task.isCancelled {
            let delay = due - ProcessInfo.processInfo.systemUptime
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if stopping || Task.isCancelled { break }
            do {
                let sinceLast = ProcessInfo.processInfo.systemUptime - (lastRequest ?? 0)
                if busy || stepPending || sinceLast < interval {
                    dropped += 1
                } else { _ = try await sample(step: nil, document: nil) }
            } catch {
                if !stopping { failure = error as? IOSWorkflowFailure ?? IOSWorkflowFailure("CAPTURE_FAILED") }
                return
            }
            due += interval
            let late = ProcessInfo.processInfo.systemUptime - due
            if late >= 0 {
                let missed = Int(late / interval) + 1
                dropped += missed
                due += Double(missed) * interval
            }
        }
    }

    func checkTime() throws {
        guard ProcessInfo.processInfo.systemUptime - startTime < duration else {
            throw IOSWorkflowFailure("CAPTURE_DURATION_EXCEEDED")
        }
    }

    private func canvas(_ viewport: IOSWorkflowTab.Viewport) -> CGSize {
        let raw = viewport.bounds
        let factor = min(tab.view.contentScaleFactor, CGFloat(maxWidth) / raw.width, 1920 / raw.height)
        return CGSize(width: max(2, Int(raw.width * factor) / 2 * 2),
                      height: max(2, Int(raw.height * factor) / 2 * 2))
    }

    private func sample(step: Int?, document expected: String?, prepare: (() -> Void)? = nil) async throws -> Bool {
        busy = true
        defer {
            busy = false
            let waiting = waiters
            waiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
        try checkTime()
        try await check()
        try tab.requireCurrent()
        let generation = tab.document
        if let expected, expected != generation { throw IOSWorkflowFailure("CAPTURE_TARGET_DOCUMENT_CHANGED") }
        let viewport = try await tab.viewport()
        // Pin dimensions, scale and zoom; scrolling may move the visible rectangle without resizing it.
        if let initial {
            let nativeResize = initial.bounds != viewport.bounds || initial.pixelRatio != viewport.pixelRatio
            let documentResize = initial.layout != viewport.layout || initial.visible.size != viewport.visible.size || initial.scale != viewport.scale
            if nativeResize || (initialDocument == generation && documentResize) { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_CHANGED") }
        }
        if initialDocument != generation {
            initial = viewport
            initialDocument = generation
        }
        guard generation == tab.document else {
            if expected != nil { throw IOSWorkflowFailure("CAPTURE_TARGET_DOCUMENT_CHANGED") }
            dropped += 1
            return false
        }
        prepare?()
        let state = try presentation.latch()
        lastRequest = state.time
        defer { presentation.releaseLatch() }
        let output = canvas(viewport)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = tab.view.bounds
        configuration.snapshotWidth = NSNumber(value: Double(output.width / max(tab.view.contentScaleFactor, 1)))
        let view = tab.view
        let source = try await IOSRendererDeadline.run(view: view, seconds: 3) {
            try await view.takeSnapshot(configuration: configuration)
        }
        try await check()
        try checkTime()
        try tab.requireCurrent()
        guard generation == tab.document && state.document == generation else {
            if expected != nil { throw IOSWorkflowFailure("CAPTURE_TARGET_DOCUMENT_CHANGED") }
            dropped += 1
            return false
        }
        let after = try await tab.viewport()
        if after != viewport {
            let scrolled = after.bounds == viewport.bounds && after.layout == viewport.layout &&
                after.visible.size == viewport.visible.size && after.scale == viewport.scale && after.pixelRatio == viewport.pixelRatio
            guard scrolled else { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_CHANGED") }
            if expected != nil { throw IOSWorkflowFailure("STALE_TARGET") }
            dropped += 1
            return false
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: output, format: format).image { render in
            source.draw(in: CGRect(origin: .zero, size: output))
            state.draw(in: render.cgContext, size: output)
        }
        guard let frame = image.cgImage else { throw IOSWorkflowFailure("CAPTURE_FRAME_FAILED") }
        try receive(frame, max(0, state.time - startTime), step, generation, viewport)
        return true
    }
}
