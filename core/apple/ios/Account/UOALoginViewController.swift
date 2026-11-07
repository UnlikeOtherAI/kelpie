import UIKit
import WebKit

/// iOS UOA login surface: a modal navigation controller hosting `UOALoginWebController` on the
/// browser tabs' shared website data store. The title names the real host; Cancel or a swipe-down
/// dismissal is the same as cancelling the login.
@MainActor
final class UOALoginViewController: UIViewController, UOALoginSurface, UIAdaptivePresentationControllerDelegate {
    private let web = UOALoginWebController(dataStore: WebViewDefaults.sharedWebsiteDataStore, userAgent: WebViewDefaults.sharedUserAgent)
    private let url: URL
    private var finish: ((UOALoginResult) -> Void)?

    /// Returns nil when there is no window to present from.
    static func present(_ url: URL, finish: @escaping (UOALoginResult) -> Void) -> UOALoginSurface? {
        guard let presenter = topViewController() else { return nil }
        let controller = UOALoginViewController(url: url, finish: finish)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.presentationController?.delegate = controller
        presenter.present(navigation, animated: true)
        return controller
    }

    private init(url: URL, finish: @escaping (UOALoginResult) -> Void) {
        self.url = url
        self.finish = finish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = web.webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = url.host ?? "Login/register"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "account.login.cancel"
        web.onURLChange = { [weak self] url in
            self?.title = url?.host ?? "Login/register"
        }
        web.onCallback = { [weak self] url in self?.end(.callback(url)) }
        web.onFailure = { [weak self] in self?.end(.failed) }
        web.load(url)
    }

    func close() {
        finish = nil
        dismissSurface()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        end(.cancelled)
    }

    @objc private func cancel() {
        end(.cancelled)
    }

    private func end(_ result: UOALoginResult) {
        guard let finish else { return }
        self.finish = nil
        dismissSurface()
        finish(result)
    }

    private func dismissSurface() {
        web.stop()
        (navigationController ?? self).presentingViewController?.dismiss(animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
