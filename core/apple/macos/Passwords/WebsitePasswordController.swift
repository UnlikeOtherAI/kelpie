import AppKit
import WebKit

@MainActor
final class WebsitePasswordController: NSObject, WKScriptMessageHandler {
    typealias Login = WebsitePasswordStore.Login
    private let store = WebsitePasswordStore()
    private var inspecting = false
    private var submitting = false
    private var watchedToken: String?

    private func usable(_ view: WKWebView) -> Bool {
        guard !view.isHiddenOrHasHiddenAncestor, let window = view.window,
              window.isKeyWindow, window.attachedSheet == nil,
              let tab = WindowRegistry.shared.allEntries().first(where: { $0.window === window })?.tabStore.activeTab
        else { return false }
        return tab.renderer.webView === view && tab.persistent && tab.partition == nil
    }

    /// Conventional HTML sign-ins arrive here before WebKit releases the form.
    func submit(_ action: WKNavigationAction, in view: WKWebView, proceed: @escaping () -> Void) -> Bool {
        guard action.navigationType == .formSubmitted, action.request.httpMethod == "POST",
              usable(view), let url = view.url, url.scheme == "https",
              let frame = action.value(forKey: "sourceFrame") as? WKFrameInfo,
              WebKitWindowPolicy.isSameOrigin(frame.securityOrigin, as: url),
              MacMicrophonePermission.origin(for: action.request.url) == MacMicrophonePermission.origin(for: url),
              !submitting else { return false }
        submitting = true
        Task {
            defer { submitting = false; proceed() }
            guard let form = try? await WebsitePasswordForm.inspect(in: view, frame: frame, url: url, submitting: true),
                  usable(view), let login = Login(url: url, username: form.username) else { return }
            await confirmSave(form, login: login)
        }
        return true
    }

    /// Called only by native browser chrome, or by a physical click in the active renderer.
    func offer(in view: WKWebView, at point: NSPoint?, explicit: Bool) {
        guard usable(view), let url = view.url, !inspecting, !submitting else { return }
        inspecting = true
        Task {
            defer { inspecting = false }
            do {
                guard let form = try await WebsitePasswordForm.inspect(in: view, frame: nil, url: url, submitting: false, click: point),
                      usable(view), !submitting, let window = view.window else {
                    if explicit { showMessage("Select a sign-in field on an HTTPS page.", in: view) }
                    return
                }
                if !explicit && form.hasPasswordField {
                    watchedToken = form.token
                    try await form.observeSubmission()
                }
                let logins = try store.logins().filter { $0.origin == form.origin }
                if logins.isEmpty && !explicit { return }
                let menu = NSMenu()
                for (index, login) in logins.enumerated() {
                    let item = menu.addItem(withTitle: login.username, action: #selector(choose(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                }
                if form.hasPasswordField && !form.username.isEmpty {
                    if !logins.isEmpty { menu.addItem(.separator()) }
                    let save = menu.addItem(withTitle: "Remember Password…", action: #selector(choose(_:)), keyEquivalent: "")
                    save.target = self
                    save.tag = -1
                }
                if menu.items.isEmpty {
                    if explicit { showMessage("Enter your username and password to save this login.", in: view) }
                    return
                }
                choice = nil
                menu.popUp(positioning: nil, at: point ?? view.convert(window.mouseLocationOutsideOfEventStream, from: nil), in: view)
                guard let choice, usable(view), view.url == url else { return }
                if choice == -1, let login = Login(url: url, username: form.username) {
                    await confirmSave(form, login: login)
                } else if logins.indices.contains(choice) {
                    let login = logins[choice]
                    let password = form.hasPasswordField ? try store.password(for: login) : ""
                    try await form.fill(login: login, password: password)
                }
            } catch { showMessage(error.localizedDescription, in: view) }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = message.webView, usable(view), !submitting,
              let url = view.url, WebKitWindowPolicy.isSameOrigin(message.frameInfo.securityOrigin, as: url),
              let body = message.body as? [String: String], let token = body["token"], token == watchedToken,
              let username = body["username"], let login = Login(url: url, username: username) else { return }
        watchedToken = nil
        let form = WebsitePasswordForm(
            webView: view, frame: message.frameInfo, origin: login.origin, token: token, username: username, hasPasswordField: true
        )
        submitting = true
        Task {
            defer { submitting = false }
            await confirmSave(form, login: login)
        }
    }

    private var choice: Int?
    @objc private func choose(_ sender: NSMenuItem) { choice = sender.tag }

    private func confirmSave(_ form: WebsitePasswordForm, login: Login) async {
        guard usable(form.webView), let window = form.webView.window else { return }
        do {
            let existing = try store.logins().contains(login)
            let alert = NSAlert()
            alert.messageText = existing ? "Update saved password?" : "Save this password?"
            alert.informativeText = "\(login.username)\n\(login.origin)"
            alert.addButton(withTitle: existing ? "Update Password" : "Save Password")
            alert.addButton(withTitle: "Not Now").keyEquivalent = "\u{1b}"
            guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn,
                  usable(form.webView) else { return }
            guard let password = try await form.readAfterConsent(), !password.isEmpty else {
                showMessage("There is no password to save in this form.", in: form.webView)
                return
            }
            try store.save(password, for: login)
            WebsitePasswordSuggestions.refresh(from: store)
        } catch { showMessage(error.localizedDescription, in: form.webView) }
    }

    private func showMessage(_ message: String, in view: WKWebView) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Saved Passwords"
        alert.informativeText = message
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
