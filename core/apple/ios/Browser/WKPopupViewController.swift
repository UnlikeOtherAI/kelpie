import UIKit
import WebKit

/// Hosts the browsing context created by WebKit for window.open. WebKit
/// supplies its opener relationship and website data store in the configuration.
@MainActor
final class WKPopupViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private weak var opener: WKWebView?

    static func present(from opener: WKWebView, configuration: WKWebViewConfiguration) -> WKWebView? {
        guard let root = opener.window?.rootViewController else { return nil }
        let presenter = topPresenter(from: root)
        guard !presenter.isBeingDismissed, !presenter.isBeingPresented else { return nil }
        let popup = WKPopupViewController(opener: opener, configuration: configuration)
        let navigation = UINavigationController(rootViewController: popup)
        navigation.modalPresentationStyle = .pageSheet
        presenter.present(navigation, animated: true)
        return popup.webView
    }

    static func dismiss(openedBy opener: WKWebView) {
        var presenter = opener.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            if let navigation = presented as? UINavigationController,
               let popup = navigation.viewControllers.first as? WKPopupViewController,
               popup.opener === opener {
                popup.close()
                return
            }
            presenter = presented
        }
    }

    private static func topPresenter(from root: UIViewController) -> UIViewController {
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        return presenter
    }

    init(opener: WKWebView, configuration: WKWebViewConfiguration) {
        self.opener = opener
        // The opener's automation bridge belongs to the opener's document.
        configuration.userContentController = WKUserContentController()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        webView.customUserAgent = opener.customUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        title = "Pop-up"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Close pop-up"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = webView }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let url = webView.url, let host = url.host, let scheme = url.scheme,
              scheme == "https" || scheme == "http" else { title = "Pop-up"; return }
        title = "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")"
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        Self.present(from: webView, configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) { close() }

    @objc private func close() { navigationController?.dismiss(animated: true) }
}
