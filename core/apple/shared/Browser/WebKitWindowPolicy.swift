import Foundation
import WebKit

/// How Kelpie hosts the browsing contexts and app links WebKit hands it.
/// Shared by the macOS and iOS WebKit delegates so both platforms agree.
enum WebKitWindowPolicy {
    enum Placement: Equatable {
        case tab
        case popup
    }

    /// Sign-in providers ask for window geometry; ordinary new-window links and
    /// `window.open(url)` do not. WebKit keeps its own pop-up decision private,
    /// so geometry is the public-API approximation: `popup=yes` without a size
    /// opens a tab, and `popup=no,width=…` opens a pop-up.
    static func placement(for features: WKWindowFeatures) -> Placement {
        let geometry: [NSNumber?] = [features.x, features.y, features.width, features.height]
        return placement(hasGeometry: geometry.contains { $0 != nil })
    }

    static func placement(hasGeometry: Bool) -> Placement {
        hasGeometry ? .popup : .tab
    }

    /// `true` for a URL the web view cannot load itself and the OS may hand to
    /// another app, such as `slack:`, `zoommtg:` or `mailto:`.
    static func opensExternalApp(_ url: URL, in configuration: WKWebViewConfiguration) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        if webSchemes.contains(scheme) || WKWebView.handlesURLScheme(scheme) { return false }
        return configuration.urlSchemeHandler(forURLScheme: scheme) == nil
    }

    private static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript"]
}

/// A page's request to open another app, as shown to the person.
struct ExternalAppRequest: Equatable {
    let url: URL
    /// `scheme://host[:port]` of the frame that asked, or `nil` when the
    /// request did not come from a page (the address bar or automation).
    let requester: String?
}

enum ExternalAppDecision: Equatable {
    /// An ordinary navigation the web view loads itself.
    case load
    /// An app link this page may not ask for now. The navigation is cancelled.
    case drop
    /// An app link to confirm with the person. The navigation is cancelled.
    case ask(ExternalAppRequest)
}

extension WebKitWindowPolicy {
    /// Decides an app link before any lookup or prompt. Only the page itself
    /// (its main frame or a frame of the same origin) may ask, and without a
    /// link activation a document may ask once, which covers launch pages that
    /// redirect to their app on load without letting a page loop the prompt.
    @MainActor
    static func externalAppDecision(for action: WKNavigationAction, in webView: WKWebView) -> ExternalAppDecision {
        guard let url = action.request.url, opensExternalApp(url, in: webView.configuration) else { return .load }
        // `sourceFrame` is annotated non-null but is nil for loads the app
        // started; KVC reads it without trusting the annotation.
        guard let source = action.value(forKey: "sourceFrame") as? WKFrameInfo else {
            return .ask(ExternalAppRequest(url: url, requester: nil))
        }
        let origin = source.securityOrigin
        guard source.isMainFrame || isSameOrigin(origin, as: webView.url),
              ExternalAppAllowance.of(webView).permits(userActivated: action.navigationType == .linkActivated) else {
            return .drop
        }
        return .ask(ExternalAppRequest(url: url, requester: label(for: origin)))
    }

    static func isSameOrigin(_ origin: WKSecurityOrigin, as url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return false }
        return origin.protocol.lowercased() == scheme
            && origin.host.lowercased() == host
            && origin.port == (url.port ?? 0)
    }

    static func label(for origin: WKSecurityOrigin) -> String? {
        guard !origin.protocol.isEmpty, !origin.host.isEmpty else { return nil }
        let port = origin.port == 0 ? "" : ":\(origin.port)"
        return "\(origin.protocol)://\(origin.host)\(port)"
    }
}

/// One ungestured app-link request per document, per web view.
@MainActor
final class ExternalAppAllowance {
    private static let allowances = NSMapTable<WKWebView, ExternalAppAllowance>.weakToStrongObjects()

    static func of(_ webView: WKWebView) -> ExternalAppAllowance {
        if let existing = allowances.object(forKey: webView) { return existing }
        let allowance = ExternalAppAllowance()
        allowances.setObject(allowance, forKey: webView)
        return allowance
    }

    private var documentMayAsk = true

    /// A new main-frame document may ask once again.
    func documentCommitted() { documentMayAsk = true }

    func permits(userActivated: Bool) -> Bool {
        if userActivated { return true }
        guard documentMayAsk else { return false }
        documentMayAsk = false
        return true
    }
}
