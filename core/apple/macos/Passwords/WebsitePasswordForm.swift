import WebKit

/// An on-demand inspection in a private WebKit world. Only the native prompt can
/// authorize reading a password. Navigation discards the captured field references.
@MainActor
struct WebsitePasswordForm {
    static let world = WKContentWorld.world(name: "Kelpie.WebsitePasswords")
    let webView: WKWebView
    let frame: WKFrameInfo?
    let origin: String
    let token: String
    let username: String
    let hasPasswordField: Bool

    static func inspect(in view: WKWebView, frame: WKFrameInfo?, url: URL, submitting: Bool, click: NSPoint? = nil) async throws -> Self? {
        guard let origin = MacMicrophonePermission.origin(for: url), url.scheme == "https" else { return nil }
        let token = UUID().uuidString
        let script = """
        if (self.origin !== origin || location.origin !== origin) return null;
        let doc = document;
        // A login widget may be embedded by its own site.
        while (doc.activeElement instanceof HTMLIFrameElement && doc.activeElement.contentDocument) {
            doc = doc.activeElement.contentDocument;
            if (doc.defaultView.origin !== origin) return null;
        }
        const active = doc.activeElement;
        if (point.length) {
            let x = point[0], y = point[1], hit = document.elementFromPoint(x, y);
            while (hit?.tagName === 'IFRAME' && hit.contentDocument) {
                const rect = hit.getBoundingClientRect();
                x -= rect.left + hit.clientLeft; y -= rect.top + hit.clientTop;
                hit = hit.contentDocument.elementFromPoint(x, y);
            }
            if (hit !== active && hit?.closest('label')?.control !== active) return null;
        }
        const visible = el => !el.disabled && !el.readOnly && el.getClientRects().length > 0;
        const inputs = Array.from(doc.querySelectorAll('input'));
        const candidates = inputs.filter(el => visible(el) && el.type === 'password' && el.autocomplete !== 'new-password' &&
            (!active?.form || el.form === active.form));
        if (candidates.length > 1) return null;
        const password = candidates[0] || null;
        if (!password && (submitting || !active || !visible(active) ||
            !(active.type === 'email' || (active.type === 'text' && active.autocomplete === 'username')))) return null;
        const form = (password || active).form;
        const names = inputs.filter(el => el.form === form && (el.type === 'email' ||
            (el.type === 'text' && !['one-time-code','new-password'].includes(el.autocomplete))));
        const account = (!password ? active : null) || names.find(el => el.autocomplete === 'username' || el.type === 'email') ||
            (names.length === 1 ? names[0] : null);
        if (form && new URL(form.action, doc.baseURI).origin !== origin) return null;
        if (submitting && (!account?.value || !password.value.length)) return null;
        if (submitting && globalThis.filledLogin?.field === password &&
            globalThis.filledLogin.username === account.value) return null;
        if (!submitting && active !== password && active !== account) return null;
        globalThis.kelpieLogin = { token, origin, password, account, doc };
        return { username: account?.value || '', hasPassword: !!password };
        """
        let point = click.map { [$0.x, view.isFlipped ? $0.y : view.bounds.maxY - $0.y] } ?? []
        let arguments: [String: Any] = ["origin": origin, "token": token, "submitting": submitting, "point": point]
        let value = try await view.callAsyncJavaScript(script, arguments: arguments, in: frame, contentWorld: world)
        guard let row = value as? [String: Any], let username = row["username"] as? String,
              let hasPassword = row["hasPassword"] as? Bool else { return nil }
        return Self(webView: view, frame: frame, origin: origin, token: token, username: username, hasPasswordField: hasPassword)
    }

    /// JavaScript sign-ins can cancel normal navigation. Observe just the
    /// focused form for one attempt. The message contains no password.
    func observeSubmission() async throws {
        let script = """
        const entry = globalThis.kelpieLogin;
        if (!entry || entry.token !== token || !entry.password?.form || !entry.account) return;
        const {password, account, doc} = entry;
        globalThis.loginWatch?.abort();
        const watch = new AbortController();
        globalThis.loginWatch = watch;
        setTimeout(() => {
            watch.abort();
            if (globalThis.kelpieLogin === entry) delete globalThis.kelpieLogin;
        }, 120000);
        password.form.addEventListener('submit', event => {
            if (!event.isTrusted || !doc.defaultView.navigator.userActivation.isActive ||
                !account.value || !password.value.length || password.type !== 'password') return;
            const username = account.value;
            if (globalThis.filledLogin?.field === password && globalThis.filledLogin.username === username) return;
            setTimeout(() => {
                if (!event.defaultPrevented || self.origin !== origin || entry !== globalThis.kelpieLogin) return;
                window.webkit.messageHandlers.kelpieLoginSubmit.postMessage({token, username});
            }, 0);
        }, {once: true, capture: true, signal: watch.signal});
        """
        _ = try await webView.callAsyncJavaScript(
            script, arguments: ["origin": origin, "token": token], in: frame, contentWorld: Self.world
        )
    }

    private static let verify = """
    const entry = globalThis.kelpieLogin;
    if (self.origin !== origin || !entry || entry.token !== token || entry.origin !== origin) return null;
    const {account, password, doc} = entry;
    if (doc.defaultView?.origin !== origin) return null;
    if (password && (!password.isConnected || password.type !== 'password' || password.disabled || password.readOnly ||
        !password.getClientRects().length)) return null;
    const form = (password || account)?.form;
    if (form && new URL(form.action, doc.baseURI).origin !== origin) return null;
    if (account && (!account.isConnected || (password && account.form !== password.form) ||
        !['text','email'].includes(account.type))) return null;
    """

    func readAfterConsent() async throws -> String? {
        // A single-page sign-in may have removed the submitted form. Only read
        // the original field in this document after the native Save action.
        let script = """
        const entry = globalThis.kelpieLogin;
        if (self.origin !== origin || entry?.token !== token || entry.doc.defaultView?.origin !== origin ||
            entry.account?.value !== username || entry.password?.type !== 'password' ||
            entry.password.ownerDocument !== entry.doc) return null;
        delete globalThis.kelpieLogin;
        return entry.password.value;
        """
        return try await webView.callAsyncJavaScript(
            script, arguments: ["origin": origin, "token": token, "username": username], in: frame, contentWorld: Self.world
        ) as? String
    }

    func fill(login: WebsitePasswordStore.Login, password: String) async throws {
        guard login.origin == origin else { return }
        let script = Self.verify + """

        if (account && !account.readOnly && !account.disabled && account.value !== username) {
            account.value = username;
            account.dispatchEvent(new Event('input', {bubbles: true}));
        }
        if (password?.isConnected && password.type === 'password' && !password.disabled && !password.readOnly &&
            password.getClientRects().length && (!password.form || new URL(password.form.action, doc.baseURI).origin === origin)) {
            password.value = secret;
            password.dispatchEvent(new Event('input', {bubbles: true}));
            password.dispatchEvent(new Event('change', {bubbles: true}));
            globalThis.filledLogin = {field: password, username};
            password.addEventListener('input', () => { delete globalThis.filledLogin; }, {once: true});
        }
        """
        _ = try await webView.callAsyncJavaScript(
            script,
            arguments: ["origin": origin, "token": token, "username": login.username, "secret": password],
            in: frame,
            contentWorld: Self.world
        )
    }
}
