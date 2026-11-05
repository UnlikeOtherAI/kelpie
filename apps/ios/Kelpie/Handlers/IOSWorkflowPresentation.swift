import UIKit

/// A noninteractive sibling of WKWebView draws the same state into the live viewport and exported frames.
@MainActor
final class IOSWorkflowPresentation: NSObject {
    struct Note {
        let text: String
        let position: String
        let until: TimeInterval
    }

    struct State {
        let size: CGSize
        let pointer: CGPoint?
        let marker: ScriptOverlayMarker?
        let note: Note?
        let time: TimeInterval
        let document: String

        func draw(in context: CGContext, size output: CGSize) {
            ScriptOverlayDrawing.draw(
                in: context,
                size: output,
                viewport: size,
                pointer: pointer,
                marker: marker,
                now: time,
                flipped: true
            )
            guard let note, time < note.until, size.width > 0, size.height > 0 else { return }
            context.saveGState()
            defer { context.restoreGState() }
            context.scaleBy(x: output.width / size.width, y: output.height / size.height)
            let width = max(1, min(400, size.width - 24))
            let y = note.position == "top" ? 16 : note.position == "center" ? size.height / 2 - 28 : size.height - 72
            let rect = CGRect(x: (size.width - width) / 2, y: y, width: width, height: 56)
            UIColor.black.withAlphaComponent(0.75).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (note.text as NSString).draw(in: rect.insetBy(dx: 8, dy: 7), withAttributes: [
                .foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 15), .paragraphStyle: style
            ])
        }
    }

    private final class Canvas: UIView {
        var state: State?
        override func draw(_ rect: CGRect) {
            guard let state, let graphics = UIGraphicsGetCurrentContext() else { return }
            state.draw(in: graphics, size: bounds.size)
        }
    }

    private let tab: IOSWorkflowTab
    private let canvas = Canvas()
    private var clock: CADisplayLink?
    private var pointer: CGPoint?
    private var marker: ScriptOverlayMarker?
    private var markerHeld = false
    private var note: Note?
    private var generation: String
    private var latched: State?

    init(tab: IOSWorkflowTab) throws {
        self.tab = tab
        generation = tab.document
        super.init()
        guard let parent = tab.view.superview else { throw IOSWorkflowFailure("TAB_NOT_VISIBLE") }
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isUserInteractionEnabled = false
        canvas.accessibilityElementsHidden = true
        canvas.translatesAutoresizingMaskIntoConstraints = false
        parent.insertSubview(canvas, aboveSubview: tab.view)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: tab.view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: tab.view.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: tab.view.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: tab.view.bottomAnchor)
        ])
        let link = CADisplayLink(target: self, selector: #selector(refresh))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        clock = link
    }

    var lastPointer: CGPoint? { generation == tab.document ? pointer : nil }
    var markerEnd: TimeInterval? { marker.map { $0.started + $0.duration } }

    func move(to point: CGPoint) {
        synchronize()
        pointer = point
        refresh()
    }

    func mark(at point: CGPoint, radius: CGFloat, settings: [String: Any], held: Bool) {
        synchronize()
        markerHeld = held
        marker = ScriptOverlayMarker(
            point: point,
            started: ProcessInfo.processInfo.systemUptime,
            duration: (settings["durationMs"] as? Double ?? 700) / 1000,
            radius: radius,
            color: ScriptOverlayDrawing.color(settings["color"] as? String ?? "#3B82F6"),
            wobble: settings["wobble"] as? Bool ?? true,
            fade: settings["fade"] as? Bool ?? true
        )
        refresh()
    }

    func beginMarkerAnimation() {
        synchronize()
        guard markerHeld, let marker else { return }
        self.marker = restarted(marker, at: ProcessInfo.processInfo.systemUptime)
        markerHeld = false
        refresh()
    }

    private func restarted(_ marker: ScriptOverlayMarker, at time: TimeInterval) -> ScriptOverlayMarker {
        ScriptOverlayMarker(
            point: marker.point,
            started: time,
            duration: marker.duration,
            radius: marker.radius,
            color: marker.color,
            wobble: marker.wobble,
            fade: marker.fade
        )
    }

    func show(_ action: [String: Any]) {
        synchronize()
        note = Note(
            text: action["text"] as? String ?? "",
            position: action["position"] as? String ?? "bottom",
            until: ProcessInfo.processInfo.systemUptime + (action["durationMs"] as? Double ?? 3000) / 1000
        )
        refresh()
    }

    func clear() {
        pointer = nil
        marker = nil
        note = nil
        latched = nil
        generation = tab.document
        refresh()
    }

    func latch() throws -> State {
        try tab.requireCurrent()
        guard let parent = tab.view.superview, parent === canvas.superview else { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_CHANGED") }
        parent.layoutIfNeeded()
        synchronize()
        let state = current()
        latched = state
        refresh()
        canvas.layer.displayIfNeeded()
        return state
    }

    func releaseLatch() {
        latched = nil
        refresh()
    }

    func finish() {
        clock?.invalidate()
        clock = nil
        canvas.removeFromSuperview()
        latched = nil
    }

    private func synchronize() {
        guard generation != tab.document else { return }
        generation = tab.document
        pointer = nil
        marker = nil
        note = nil
        latched = nil
    }

    private func current() -> State {
        let now = ProcessInfo.processInfo.systemUptime
        return State(
            size: tab.view.bounds.size,
            pointer: pointer,
            marker: markerHeld ? marker.map { restarted($0, at: now) } : marker,
            note: note,
            time: now,
            document: generation
        )
    }

    @objc private func refresh() {
        synchronize()
        let visible = (try? tab.requireCurrent()) != nil && canvas.superview === tab.view.superview &&
            tab.view.window?.windowScene?.activationState == .foregroundActive
        canvas.isHidden = !visible
        canvas.state = visible ? (latched ?? current()) : nil
        canvas.setNeedsDisplay()
    }
}
