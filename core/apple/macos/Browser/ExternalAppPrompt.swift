import AppKit

/// Asks before a page hands a link to another app, as Safari and Chrome do.
@MainActor
enum ExternalAppPrompt {
    private static var inputMonitor: Any?

    /// Records clicks and key presses in browser windows, so script a click
    /// runs (a "Launch app" button) may ask again. Input to a sheet, such as
    /// this prompt's own Cancel, does not count, so cancelling cannot re-arm it.
    static func trackUserInput() {
        guard inputMonitor == nil else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
            if let window = event.window, window.sheetParent == nil, !(window is NSPanel) {
                MainActor.assumeIsolated { ExternalAppAllowance.lastUserInput = Date() }
            }
            return event
        }
    }

    /// Shows a sheet naming the requesting site and the app macOS resolved for
    /// the link. Nothing is shown when no app handles the link, the page is not
    /// on screen, or its window already shows a sheet.
    static func present(_ request: ExternalAppRequest, from view: NSView) {
        guard isOnScreen(view), let window = view.window, window.attachedSheet == nil,
              let app = NSWorkspace.shared.urlForApplication(toOpen: request.url) else { return }
        let name = displayName(of: app)
        let alert = NSAlert()
        alert.messageText = "Open “\(name)”?"
        alert.informativeText = "\(request.requester ?? "This page") wants to open this app."
        alert.icon = NSWorkspace.shared.icon(forFile: app.path)
        alert.addButton(withTitle: "Open \(name)")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak view] response in
            guard response == .alertFirstButtonReturn, let view, isOnScreen(view) else { return }
            // Launch the app the person agreed to, even if the default changed.
            NSWorkspace.shared.open([request.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func isOnScreen(_ view: NSView) -> Bool {
        guard let window = view.window else { return false }
        return window.isVisible && !view.isHiddenOrHasHiddenAncestor
    }

    private static func displayName(of app: URL) -> String {
        let bundle = Bundle(url: app)
        let info = bundle?.localizedInfoDictionary ?? [:]
        let plist = bundle?.infoDictionary ?? [:]
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = (info[key] ?? plist[key]) as? String, !name.isEmpty { return name }
        }
        return app.deletingPathExtension().lastPathComponent
    }
}
