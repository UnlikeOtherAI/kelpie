import AuthenticationServices
import UIKit
import WebKit

/// Opens the current page URL in an ASWebAuthenticationSession (Safari-backed sheet)
/// so the user can authenticate with Safari's saved passwords and cookies,
/// then syncs cookies back into the WKWebView.
@MainActor
final class SafariAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private weak var webView: WKWebView?

    func authenticate(url: URL, webView: WKWebView) {
        self.webView = webView

        // callbackURLScheme: nil — no redirect expected. The user logs in,
        // taps Done, and the completion fires so we can sync cookies + reload.
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
            Task { @MainActor in
                await self?.syncCookiesAndReload()
            }
        }
        session.prefersEphemeralWebBrowserSession = false // share Safari's cookies + passwords
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    private func syncCookiesAndReload() async {
        guard let webView else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        // ASWebAuthenticationSession with prefersEphemeralWebBrowserSession=false
        // shares cookies with Safari. Grab them from the shared storage.
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                await cookieStore.setCookie(cookie)
            }
        }

        webView.reload()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            webView?.window ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
