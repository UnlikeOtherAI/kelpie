import WebKit

/// Weak proxy for `WKScriptMessageHandler` registrations.
///
/// `WKUserContentController.add(_:name:)` retains the handler strongly. When the
/// registered handler also retains the `WKWebView` (directly or via a coordinator
/// that owns it), this creates a retain cycle that prevents the WKWebView from
/// being released — bridge scripts keep running, tabs leak, and memory grows
/// across navigations.
///
/// `WeakScriptMessageHandler` holds the real target weakly so the cycle is
/// broken: registrar -> proxy (strong) -> target (weak) -> webView (strong).
/// Closing the tab releases the target; the proxy then becomes a harmless no-op.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
