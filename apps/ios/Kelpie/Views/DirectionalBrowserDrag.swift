import SwiftUI
import UIKit

/// The recognizer rejects the wrong axis before claiming a touch. A SwiftUI
/// DragGesture on a grid card would otherwise prevent its ScrollView scrolling.
struct DirectionalBrowserDrag: UIViewRepresentable {
    enum Axis { case horizontal, upward }
    let axis: Axis
    var enabled = true
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> DragRegion {
        let view = DragRegion()
        view.configure(self)
        return view
    }

    func updateUIView(_ uiView: DragRegion, context: Context) { uiView.configure(self) }

    final class DragRegion: UIView, UIGestureRecognizerDelegate {
        private var configuration: DirectionalBrowserDrag?
        private weak var installedWindow: UIWindow?
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))

        func configure(_ configuration: DirectionalBrowserDrag) {
            self.configuration = configuration
            pan.isEnabled = configuration.enabled
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installedWindow?.removeGestureRecognizer(pan)
            installedWindow = window
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            window?.addGestureRecognizer(pan)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window, !isHidden else { return false }
            guard convert(bounds, to: window).contains(touch.location(in: window)) else { return false }
            var responder: UIResponder? = self
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard let controller = responder as? UIViewController,
                  controller.presentedViewController == nil,
                  touch.view?.isDescendant(of: controller.view) == true else { return false }
            var ancestor: UIView? = self
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 { return false }
                if view.clipsToBounds && !view.bounds.contains(touch.location(in: view)) { return false }
                ancestor = view.superview
            }
            return true
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: window)
            switch configuration?.axis {
            case .horizontal: return abs(velocity.x) > abs(velocity.y) * 1.25
            case .upward: return velocity.y < 0 && abs(velocity.y) > abs(velocity.x) * 1.25
            case nil: return false
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        @objc private func dragged() {
            guard let configuration else { return }
            let translation = pan.translation(in: window)
            let velocity = pan.velocity(in: window)
            let distance = configuration.axis == .horizontal ? translation.x : translation.y
            let speed = configuration.axis == .horizontal ? velocity.x : velocity.y
            switch pan.state {
            case .changed: configuration.onChange(distance)
            case .ended: configuration.onEnd(distance, speed)
            case .cancelled, .failed: configuration.onEnd(0, 0)
            default: break
            }
        }
    }
}
