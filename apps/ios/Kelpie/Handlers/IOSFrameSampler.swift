import UIKit
import WebKit

/// One in-flight WebKit viewport sample. Every accepted frame carries its request-time overlay and document stamp.
@MainActor
final class IOSFrameSampler {
    typealias Receiver = (CGImage, TimeInterval, Int?, String, IOSWorkflowTab.Viewport) throws -> Bool
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
    private var lastAdmitted = false
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

    var recordsMotion: Bool { continuous }
    var elapsed: TimeInterval { min(duration, ProcessInfo.processInfo.systemUptime - startTime) }

    func start() async throws {
        guard continuous else { return }
        while !(try await sample(step: nil, document: nil)) { try checkTime() }
        ticker = Task { @MainActor [weak self] in await self?.periodic() }
    }

    @discardableResult
    func step(_ index: Int?, document: String? = nil, prepare: (() -> Void)? = nil) async throws -> Bool {
        stepPending = true
        defer { stepPending = false }
        while busy { await withCheckedContinuation { waiters.append($0) } }
        if let failure { throw failure }
        guard !stopping else { throw IOSWorkflowFailure("CAPTURE_STOPPED") }
        if !continuous, index == nil { prepare?(); return true }
        if continuous, let lastRequest { try await wait(until: lastRequest + 1.0 / Double(fps), document: document) }
        while !(try await sample(step: index, document: document, prepare: prepare)) { try checkTime() }
        return lastAdmitted
    }

    /// Require actual admission by every requested encoder. A rejected video frame cannot authorize the input.
    /// A full interval measured after acknowledgement also gives the held frame its requested duration.
    func markBeforeInput(_ index: Int?, document: String, prepare: @escaping () -> Void) async throws {
        var accepted = try await step(index, document: document, prepare: prepare)
        guard continuous else { return }
        while !accepted { accepted = try await step(nil, document: document) }
        try await wait(until: ProcessInfo.processInfo.systemUptime + 1.0 / Double(fps), document: document)
    }

    private func wait(until deadline: TimeInterval, document: String?) async throws {
        repeat {
            try await check()
            try checkTime()
            if let document, tab.document != document { throw IOSWorkflowFailure("CAPTURE_TARGET_DOCUMENT_CHANGED") }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { return }
            try await Task.sleep(nanoseconds: UInt64(min(0.05, remaining) * 1_000_000_000))
        } while true
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

    static func diagnostic(_ reason: String) {
        #if DEBUG
        print("[WorkflowCapture] reason=" + reason)
        #endif
    }

    // Pin dimensions, scale and zoom; scrolling may move the visible rectangle without resizing it.
    private func pinViewport(_ viewport: IOSWorkflowTab.Viewport, generation: String) throws {
        try requirePinnedNativeViewport(viewport)
        if let initial, initialDocument == generation {
            let documentResize = initial.layout != viewport.layout || initial.visible.size != viewport.visible.size || initial.scale != viewport.scale
            if documentResize {
                Self.diagnostic(Self.resizeReason(initial: initial, viewport: viewport))
                Self.geometryDiagnostic(before: initial, after: viewport)
                throw IOSWorkflowFailure("CAPTURE_VIEWPORT_CHANGED")
            }
        }
        if initialDocument != generation {
            initial = viewport
            initialDocument = generation
        }
    }

    private func requirePinnedNativeViewport(_ viewport: IOSWorkflowTab.Viewport) throws {
        guard let initial else { return }
        guard initial.bounds == viewport.bounds, initial.content == viewport.content, initial.pixelRatio == viewport.pixelRatio else {
            Self.diagnostic(Self.resizeReason(initial: initial, viewport: viewport))
            Self.geometryDiagnostic(before: initial, after: viewport)
            throw IOSWorkflowFailure("CAPTURE_VIEWPORT_CHANGED")
        }
    }

    private static func resizeReason(initial: IOSWorkflowTab.Viewport, viewport: IOSWorkflowTab.Viewport) -> String {
        if initial.bounds != viewport.bounds { return "native-bounds" }
        if initial.content != viewport.content { return "native-insets" }
        if initial.pixelRatio != viewport.pixelRatio { return "pixel-ratio" }
        if initial.layout != viewport.layout { return "layout-size" }
        if initial.visible.size != viewport.visible.size { return "visible-size" }
        return "scale"
    }

    private static func geometryDiagnostic(before: IOSWorkflowTab.Viewport, after: IOSWorkflowTab.Viewport) {
        #if DEBUG
        func values(_ viewport: IOSWorkflowTab.Viewport) -> [CGFloat] {
            [viewport.bounds.width, viewport.bounds.height, viewport.layout.width, viewport.layout.height,
             viewport.visible.width, viewport.visible.height, viewport.scale, viewport.pixelRatio]
        }
        let first = values(before), second = values(after)
        guard (first + second).allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100_000 }) else { return }
        func encode(_ values: [CGFloat]) -> String {
            values.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double($0)) }.joined(separator: ",")
        }
        print("[WorkflowCaptureGeometry] before=" + encode(first) + " after=" + encode(second))
        #endif
    }

    #if DEBUG
    private static func nativeInsets(_ view: WKWebView) -> [CGFloat] {
        let safe = view.safeAreaInsets
        let adjusted = view.scrollView.adjustedContentInset
        let content = view.scrollView.contentInset
        let window = view.window?.safeAreaInsets ?? .zero
        return [safe.top, safe.bottom, adjusted.top, adjusted.bottom, content.top, content.bottom,
                window.top, window.bottom, CGFloat(view.scrollView.contentInsetAdjustmentBehavior.rawValue)]
    }

    static func projectionDiagnostic(view: WKWebView, viewport: IOSWorkflowTab.Viewport, css: CGPoint, point: CGPoint) {
        let insets = view.scrollView.adjustedContentInset
        let offset = view.scrollView.contentOffset
        let values = [viewport.bounds.width, viewport.bounds.height, viewport.visible.minX, viewport.visible.minY,
                      viewport.visible.width, viewport.visible.height, viewport.scale, insets.top, insets.bottom,
                      insets.left, insets.right, offset.x, offset.y, css.x, css.y, point.x, point.y]
        guard values.allSatisfy({ $0.isFinite && abs($0) <= 10000 }) else { return }
        let encoded = values.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double($0)) }
        print("[WorkflowProjection] values=" + encoded.joined(separator: ","))
    }

    private static func insetsDiagnostic(before: [CGFloat], after: [CGFloat]) {
        guard before.count == 9, after.count == 9,
              (before + after).allSatisfy({ $0.isFinite && abs($0) <= 10_000 }) else { return }
        func encode(_ values: [CGFloat]) -> String {
            values.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double($0)) }.joined(separator: ",")
        }
        print("[WorkflowCaptureInsets] before=" + encode(before) + " after=" + encode(after))
    }
    #endif

    private func canvas(_ viewport: IOSWorkflowTab.Viewport) -> CGSize {
        let raw = viewport.bounds
        let factor = min(tab.view.contentScaleFactor, CGFloat(maxWidth) / raw.width, 1920 / raw.height)
        return CGSize(width: max(2, Int(raw.width * factor) / 2 * 2),
                      height: max(2, Int(raw.height * factor) / 2 * 2))
    }

    private func viewportForSample(generation: String, expected: String?) async throws -> IOSWorkflowTab.Viewport? {
        if initialDocument == generation { return try await tab.viewport() }
        let viewport = try await IOSCaptureViewportStability.wait(
            deadline: ProcessInfo.processInfo.systemUptime + 2,
            check: { [self] in try await check(); try checkTime() },
            read: { [self] in
                guard generation == tab.document else { return nil }
                let viewport = try await tab.viewport()
                try requirePinnedNativeViewport(viewport)
                guard generation == tab.document else { return nil }
                return viewport
            },
            admissible: { [self] viewport in
                let insets = tab.view.scrollView.adjustedContentInset
                return IOSCaptureViewportStability.matchesInsets(
                    viewport, top: insets.top, bottom: insets.bottom, left: insets.left, right: insets.right
                )
            }
        )
        guard let viewport else {
            if expected != nil { throw IOSWorkflowFailure("CAPTURE_TARGET_DOCUMENT_CHANGED") }
            dropped += 1
            return nil
        }
        return viewport
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
        guard let viewport = try await viewportForSample(generation: generation, expected: expected) else { return false }
        try pinViewport(viewport, generation: generation)
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
        #if DEBUG
        let insetsBefore = Self.nativeInsets(view)
        #endif
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
            let scrolled = after.bounds == viewport.bounds && after.content == viewport.content && after.layout == viewport.layout &&
                after.visible.size == viewport.visible.size && after.scale == viewport.scale && after.pixelRatio == viewport.pixelRatio
            guard scrolled else {
                Self.diagnostic("snapshot-" + Self.resizeReason(initial: viewport, viewport: after))
                Self.geometryDiagnostic(before: viewport, after: after)
                #if DEBUG
                Self.insetsDiagnostic(before: insetsBefore, after: Self.nativeInsets(view))
                #endif
                throw IOSWorkflowFailure("CAPTURE_VIEWPORT_CHANGED")
            }
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
        lastAdmitted = try receive(frame, max(0, state.time - startTime), step, generation, viewport)
        return true
    }
}
