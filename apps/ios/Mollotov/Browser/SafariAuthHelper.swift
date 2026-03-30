import AuthenticationServices
import WebKit

/// Opens the current page URL in an ASWebAuthenticationSession (Safari-backed sheet)
/// so the user can authenticate with Safari's saved passwords and cookies,
/// then syncs cookies back into the WKWebView.
@MainActor
final class SafariAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private weak var webView: WKWebView?
    private var onComplete: (() -> Void)?

    func authenticate(url: URL, webView: WKWebView, from anchor: ASPresentationAnchor?, onComplete: @escaping () -> Void) {
        self.webView = webView
        self.onComplete = onComplete

        // Use a custom callback scheme — the session will end when Safari redirects to it,
        // OR when the user taps "Done" to dismiss the sheet.
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "mollotov-auth") { [weak self] _, _ in
            // Whether success or cancel, sync cookies and reload
            Task { @MainActor in
                await self?.syncCookiesAndReload()
            }
        }
        session.prefersEphemeralWebBrowserSession = false // Share Safari's cookies
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    private func syncCookiesAndReload() async {
        guard let webView else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        // Grab all cookies from the shared HTTPCookieStorage (populated by Safari session)
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                await cookieStore.setCookie(cookie)
            }
        }

        // Reload the page — should now be authenticated
        webView.reload()
        onComplete?()
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
