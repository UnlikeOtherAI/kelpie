import UIKit
import WebKit

/// Asks before a page hands a link to another app, as Safari does.
@MainActor
enum ExternalAppPrompt {
    /// Shows an alert naming the requesting site. iOS cannot resolve the app
    /// for an arbitrary scheme, so the alert names the link's scheme instead.
    /// Nothing is shown while the page is off screen or another alert is up.
    static func present(_ request: ExternalAppRequest, from webView: WKWebView) {
        guard let root = webView.window?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIAlertController), !presenter.isBeingPresented, !presenter.isBeingDismissed else { return }
        let scheme = request.url.scheme ?? "app"
        let alert = UIAlertController(
            title: "Open in another app?",
            message: "\(request.requester ?? "This page") wants to open a “\(scheme):” link in another app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak webView] _ in
            guard webView?.window != nil else { return }
            UIApplication.shared.open(request.url)
        })
        presenter.present(alert, animated: true)
    }

    /// Applies the shared app-link rules to a navigation and answers WebKit.
    static func decide(
        _ action: WKNavigationAction,
        in webView: WKWebView,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        switch WebKitWindowPolicy.externalAppDecision(for: action, in: webView) {
        case .load:
            decisionHandler(action.shouldPerformDownload ? .download : .allow)
        case .drop:
            decisionHandler(.cancel)
        case .ask(let request):
            decisionHandler(.cancel)
            present(request, from: webView)
        }
    }
}
