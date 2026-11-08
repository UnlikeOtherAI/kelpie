import UIKit

/// Moves one complete browser controller between a host view and a scene window.
@MainActor
public final class KelpieBrowserPresentation {
    public let session: KelpieBrowserSession
    public let viewController: UIViewController
    private var window: UIWindow?

    public init(session: KelpieBrowserSession) {
        self.session = session
        viewController = session.makeViewController()
    }

    public func attach(to parent: UIViewController) {
        precondition(parent !== viewController)
        detach()
        parent.addChild(viewController)
        viewController.view.frame = parent.view.bounds
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(viewController.view)
        viewController.didMove(toParent: parent)
    }

    /// The host chooses the scene, including an iPad external-display scene.
    public func present(in scene: UIWindowScene) {
        detach()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = viewController
        window.isHidden = false
        self.window = window
    }

    public func detach() {
        if let window {
            window.isHidden = true
            window.rootViewController = nil
            self.window = nil
        }
        if viewController.parent != nil {
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
        }
    }
}
