import Foundation
import WebKit

/// How a login surface ended. Cancellation is the user's choice and is never reported as an error.
enum UOALoginResult: Equatable {
    case callback(URL)
    case cancelled
    case failed
}

/// A presented UOA login surface. `close()` dismisses it without reporting a result.
@MainActor
protocol UOALoginSurface: AnyObject {
    func close()
}

/// Navigation policy for the UOA login view: the OAuth callback ends the login, https pages load,
/// and everything else is refused.
enum UOALoginNavigation: Equatable {
    case allow
    case callback(URL)
    case deny

    static func decide(_ url: URL?) -> Self {
        guard let url, let scheme = url.scheme?.lowercased() else { return .deny }
        if scheme == UOAAuthorization.callbackScheme { return .callback(url) }
        if scheme == "https" { return .allow }
        if url.absoluteString.lowercased() == "about:blank" { return .allow }
        return .deny
    }

    /// The origin shown to the user, so the real page behind the login view is always visible.
    static func origin(of url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        guard let port = url.port, port != (scheme == "https" ? 443 : 80) else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    static func title(for url: URL?) -> String {
        guard let origin = origin(of: url) else { return "Login/register" }
        return "Login/register — \(origin)"
    }
}

/// Hosts the UOA login page in a plain WKWebView backed by the same website data store as
/// unpartitioned browser tabs, so every cookie and storage item the login sets (Google's included)
/// is shared with them. It carries no user scripts or script message handlers, and it is not a tab:
/// automation, tab lists, history and session restore never see it.
@MainActor
final class UOALoginWebController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    /// Called once with the callback URL; the surface owner closes the view.
    var onCallback: ((URL) -> Void)?
    /// Called when the first page could not be loaded at all.
    var onFailure: (() -> Void)?
    var onURLChange: ((URL?) -> Void)?
    private var committed = false
    private var urlObservation: NSKeyValueObservation?

    init(dataStore: WKWebsiteDataStore, userAgent: String) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated { self?.onURLChange?(webView.url) }
        }
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Stops loading and detaches every callback so a closed surface can never report again.
    func stop() {
        onCallback = nil
        onFailure = nil
        onURLChange = nil
        urlObservation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        switch UOALoginNavigation.decide(navigationAction.request.url) {
        case .allow:
            decisionHandler(.allow)
        case .deny:
            decisionHandler(.cancel)
        case .callback(let url):
            decisionHandler(.cancel)
            let callback = onCallback
            onCallback = nil
            callback?(url)
        }
    }

    /// Provider pop-ups and target=_blank handoffs continue in this same view.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        committed = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failure = error as NSError
        // Policy cancellations (the callback and refused schemes) are not load failures, and once a
        // page is showing the user can read any later error there or cancel.
        guard !committed, failure.domain == NSURLErrorDomain, failure.code != NSURLErrorCancelled else { return }
        let report = onFailure
        onFailure = nil
        report?()
    }
}
