import AuthenticationServices
import AppKit

/// Opens a URL in ASWebAuthenticationSession for Safari-backed authentication,
/// then syncs cookies back into the active renderer.
@MainActor
final class SafariAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    weak var handlerContext: HandlerContext?

    func authenticate(url: URL) {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
            Task { @MainActor in
                await self?.syncCookiesAndReload()
            }
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    private func syncCookiesAndReload() async {
        guard let ctx = handlerContext, let renderer = ctx.renderer else { return }
        if let cookies = HTTPCookieStorage.shared.cookies {
            await renderer.setCookies(cookies)
        }
        if let url = renderer.currentURL {
            renderer.load(url: url)
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        }
    }
}
