import AuthenticationServices
import UIKit
import WebKit

/// Errors thrown while running a Safari-backed authentication session.
enum SafariAuthError: Error {
    /// The webView reference was nil at completion (tab closed, view torn down).
    case webViewUnavailable
    /// The system reported a failure from `ASWebAuthenticationSession`. The
    /// underlying error is preserved verbatim — common cases include the user
    /// cancelling the sheet and the session failing to present.
    case session(Error)
}

/// Opens the current page URL in an ASWebAuthenticationSession (Safari-backed sheet)
/// so the user can authenticate with Safari's saved passwords and cookies,
/// then syncs cookies back into the WKWebView.
///
/// Errors from the underlying session are propagated through `authenticate` —
/// callers can surface cancellations or presentation failures rather than
/// silently treating them as success. Cookie sync still runs on success.
@MainActor
final class SafariAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private weak var webView: WKWebView?

    /// Starts the Safari authentication sheet. Resumes when the user dismisses
    /// the sheet (or the system tears it down). Throws if the session fails or
    /// the webView is no longer available for cookie sync.
    func authenticate(url: URL, webView: WKWebView) async throws {
        self.webView = webView

        let outcome: Result<URL?, Error> = await withCheckedContinuation { continuation in
            // callbackURLScheme: nil — no redirect expected. The user logs in,
            // taps Done, and the completion fires so we can sync cookies + reload.
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { callbackURL, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(callbackURL))
                }
            }
            session.prefersEphemeralWebBrowserSession = false // share Safari's cookies + passwords
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }

        defer { self.session = nil }

        switch outcome {
        case .failure(let underlying):
            throw SafariAuthError.session(underlying)
        case .success:
            guard let webView = self.webView else {
                throw SafariAuthError.webViewUnavailable
            }
            await syncCookiesAndReload(webView: webView)
        }
    }

    private func syncCookiesAndReload(webView: WKWebView) async {
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
