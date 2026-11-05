import AppKit
import CoreText

/// A renderer-scoped native overlay; movement never changes DOM hover or the OS cursor.
@MainActor
final class ScriptPresentation {
    typealias Marker = ScriptOverlayMarker
    private final class Canvas: NSView {
        weak var presentation: ScriptPresentation?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            guard let graphics = NSGraphicsContext.current?.cgContext else { return }
            #if DEBUG
            presentation?.recordScreenDraw()
            #endif
            presentation?.draw(in: graphics, size: bounds.size, flipped: true)
        }
    }

    private let canvas = Canvas()
    #if DEBUG
    private let rendererName: String
    private var tracingMove = false
    private var drawCount = 0
    private var lastDraw: TimeInterval = 0
    private var maximumDrawGap: TimeInterval = 0
    private var tracedMoves = 0
    #endif
    private var timer: Timer?
    private var documentObserver: NSObjectProtocol?
    private var marker: Marker?
    private(set) weak var markerWindow: NSWindow?
    private(set) var markerGeometry: ScriptMarkerGeometry?
    private(set) var markerDocument: String?
    private var pointer: CGPoint?
    private var commentary: String?
    private var held = false
    private var heldTime: TimeInterval = 0
    var viewportSize: CGSize { canvas.bounds.size }

    init(renderer: any RendererEngine) {
        #if DEBUG
        rendererName = ["webkit", "chromium"].contains(renderer.engineName) ? renderer.engineName : "other"
        #endif
        let view = renderer.makeView()
        canvas.frame = renderer.scriptViewportRect
        canvas.presentation = self
        view.addSubview(canvas, positioned: .above, relativeTo: nil)
        documentObserver = NotificationCenter.default.addObserver(
            forName: .kelpieBrowserDocumentChanged, object: renderer, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.clear() } }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.canvas.needsDisplay = true }
        }
    }

    func clear() {
        marker = nil
        markerWindow = nil
        markerGeometry = nil
        markerDocument = nil
        pointer = nil
        commentary = nil
        held = false
        canvas.needsDisplay = true
    }

    /// A completed run may leave only its noninteractive final marker until expiry.
    func keepMarkerOnly() {
        pointer = nil
        commentary = nil
        canvas.needsDisplay = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        canvas.removeFromSuperview()
        if let documentObserver { NotificationCenter.default.removeObserver(documentObserver) }
        documentObserver = nil
    }

    /// The clock stays at zero until an actual legal movie sample contains the marker.
    func indicate(at point: CGPoint, options: [String: Any], tab: ScriptWorkflowTab, hold: Bool = false) {
        markerWindow = tab.view.window
        markerGeometry = markerWindow.map { ScriptMarkerGeometry(tab: tab, window: $0) }
        markerDocument = tab.document
        heldTime = ProcessInfo.processInfo.systemUptime
        held = hold
        marker = Marker(
            point: point,
            started: heldTime,
            duration: Double(options["durationMs"] as? Int ?? 700) / 1000,
            radius: CGFloat(options["radius"] as? Double ?? 20),
            color: ScriptOverlayDrawing.color(options["color"] as? String ?? "#3B82F6"),
            wobble: options["wobble"] as? Bool ?? true,
            fade: options["fade"] as? Bool ?? true
        )
        canvas.needsDisplay = true
    }

    func show(_ step: [String: Any]) {
        commentary = String((step["text"] as? String ?? "").prefix(2000))
        canvas.needsDisplay = true
    }

    func releaseMarker() {
        guard held, let previous = marker else { return }
        marker = Marker(
            point: previous.point,
            started: ProcessInfo.processInfo.systemUptime,
            duration: previous.duration,
            radius: previous.radius,
            color: previous.color,
            wobble: previous.wobble,
            fade: previous.fade
        )
        held = false
        canvas.needsDisplay = true
    }

    var markerEnd: TimeInterval? {
        guard !held, let marker else { return nil }
        return marker.started + marker.duration
    }

    func move(to end: CGPoint, options: [String: Any], check: () async throws -> Void) async throws {
        guard options["enabled"] as? Bool == true else { try await check(); return }
        let start = pointer ?? CGPoint(x: max(0, end.x - 100), y: max(0, end.y - 70))
        let duration = Double(options["durationMs"] as? Int ?? 350)
        let began = ProcessInfo.processInfo.systemUptime
        #if DEBUG
        let tracing = duration == 350 && tracedMoves < 2
        var updates = 0
        var maximumUpdateGap: TimeInterval = 0
        var previousUpdate = began
        var completed = false
        if tracing { tracedMoves += 1; tracingMove = true; drawCount = 0; lastDraw = began; maximumDrawGap = 0 }
        defer {
            if tracing {
                tracingMove = false
                let ended = ProcessInfo.processInfo.systemUptime
                let elapsed = Int(min(max((ended - began) * 1000, 0), 99999))
                let updateGap = Int(min(max(maximumUpdateGap * 1000, 0), 99999))
                let drawGap = Int(min(max(max(maximumDrawGap, ended - lastDraw) * 1000, 0), 99999))
                print("[WorkflowPointerTiming] engine=\(rendererName) elapsed=\(elapsed) updates=\(min(updates, 99999)) " +
                      "updateGap=\(updateGap) draws=\(min(drawCount, 99999)) drawGap=\(drawGap) complete=\(completed ? 1 : 0)")
            }
        }
        #endif
        repeat {
            try await check()
            let now = ProcessInfo.processInfo.systemUptime
            #if DEBUG
            if tracing { updates += 1; maximumUpdateGap = max(maximumUpdateGap, now - previousUpdate); previousUpdate = now }
            #endif
            let progress = kelpie_script_progress((now - began) * 1000, duration)
            pointer = Self.path(from: start, to: end, progress: progress, curve: options["curve"] as? String ?? "s")
            canvas.needsDisplay = true
            if progress >= 1 {
                #if DEBUG
                completed = true
                #endif
                break
            }
            try await Task.sleep(nanoseconds: 16_000_000)
        } while true
    }

    #if DEBUG
    private func recordScreenDraw() {
        guard tracingMove else { return }
        let now = ProcessInfo.processInfo.systemUptime
        maximumDrawGap = max(maximumDrawGap, now - lastDraw)
        lastDraw = now
        drawCount += 1
    }
    #endif

    static func path(from start: CGPoint, to end: CGPoint, progress: Double, curve: String) -> CGPoint {
        ScriptOverlayDrawing.path(from: start, to: end, progress: progress, curve: curve)
    }

    struct Frame {
        let viewport: CGSize
        let pointer: CGPoint?
        let marker: Marker?
        let commentary: String?
        let time: TimeInterval

        func draw(in graphics: CGContext, size: CGSize, flipped: Bool = false) {
            ScriptOverlayDrawing.draw(in: graphics, size: size, viewport: viewport, pointer: pointer, marker: marker, now: time, flipped: flipped)
            if let commentary, !commentary.isEmpty {
                graphics.saveGState()
                if flipped { graphics.translateBy(x: 0, y: size.height); graphics.scaleBy(x: 1, y: -1) }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: max(12, size.width / 80)),
                    .foregroundColor: NSColor.white
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: commentary, attributes: attributes))
                graphics.setFillColor(CGColor(gray: 0, alpha: 0.8))
                graphics.fill(CGRect(x: 8, y: 8, width: max(0, size.width - 16), height: 40))
                graphics.textPosition = CGPoint(x: 16, y: 22)
                CTLineDraw(line, graphics)
                graphics.restoreGState()
            }

        }
    }

    static func exposedMarker(_ marker: Marker?, time: TimeInterval) -> Marker? {
        guard let marker, ScriptOverlayDrawing.markerIsVisible(marker, now: time) else { return nil }
        return marker
    }

    func frame() -> Frame {
        let time = held ? heldTime : ProcessInfo.processInfo.systemUptime
        return Frame(
            viewport: canvas.bounds.size,
            pointer: pointer,
            marker: Self.exposedMarker(marker, time: time),
            commentary: commentary,
            time: time
        )
    }

    func draw(in graphics: CGContext, size: CGSize, flipped: Bool = false) {
        frame().draw(in: graphics, size: size, flipped: flipped)
    }
}
