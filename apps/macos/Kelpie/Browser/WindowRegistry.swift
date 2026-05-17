import AppKit
import Foundation
import SwiftUI

/// Tracks every open browser window and its per-window `TabStore` so HTTP
/// handlers can route `(windowId, tabId)` requests to the correct shell.
///
/// macOS Kelpie supports multiple top-level windows that share one HTTP server
/// but each owns an independent tab list. A single shared `TabStore` would
/// resolve `tabId=X` against the wrong window if X happens to exist in a
/// different window than the LLM intended. The registry fixes that by:
///
/// 1. Assigning every window a stable `windowId` (UUID) at construction time.
/// 2. Holding a weak reference to the `NSWindow` plus a strong reference to
///    the window's `TabStore` and its tab-mutation callbacks.
/// 3. Exposing lookups by `windowId`, by `tabId`, and a "current key window"
///    fallback for requests that do not specify a window.
@MainActor
final class WindowRegistry {
    static let shared = WindowRegistry()

    /// Mutation hooks the UI installs so HTTP handlers can drive the tab
    /// lifecycle without reaching directly into SwiftUI state. Each window
    /// owns its own callbacks because new-tab/switch-tab/close-tab must affect
    /// only the window the request targets.
    struct Callbacks {
        var onNewTab: () -> Tab
        var onSwitchTab: (UUID) -> Void
        var onCloseTab: (UUID) -> Void
        var onWillLoad: () -> Void
    }

    final class Entry {
        let id: String
        weak var window: NSWindow?
        let tabStore: TabStore
        var callbacks: Callbacks?

        init(id: String, window: NSWindow?, tabStore: TabStore) {
            self.id = id
            self.window = window
            self.tabStore = tabStore
        }
    }

    private var entries: [String: Entry] = [:]
    private var registrationOrder: [String] = []

    private init() {}

    /// Register a window/tabStore pair. Returns the stable `windowId`. Safe to
    /// call repeatedly with the same id; subsequent calls refresh the weak
    /// window reference but preserve any installed callbacks.
    @discardableResult
    func register(id: String, window: NSWindow?, tabStore: TabStore) -> String {
        if let existing = entries[id] {
            existing.window = window
            return id
        }
        entries[id] = Entry(id: id, window: window, tabStore: tabStore)
        registrationOrder.append(id)
        return id
    }

    /// Install or replace the mutation callbacks for a window.
    func installCallbacks(for id: String, callbacks: Callbacks) {
        entries[id]?.callbacks = callbacks
    }

    /// Remove a window from the registry. Called when the window closes.
    func unregister(id: String) {
        entries.removeValue(forKey: id)
        registrationOrder.removeAll { $0 == id }
    }

    /// Look up the entry for a specific window id.
    func entry(for windowId: String) -> Entry? {
        entries[windowId]
    }

    /// Look up the entry whose tab store currently contains `tabId`.
    /// Tab UUIDs are globally unique so this resolves a tab back to its window.
    func entry(containingTabId tabId: UUID) -> Entry? {
        for id in registrationOrder {
            guard let entry = entries[id] else { continue }
            if entry.tabStore.tabs.contains(where: { $0.id == tabId }) {
                return entry
            }
        }
        return nil
    }

    /// Entry to use when the request does not name a window. Prefers the key
    /// window, then the main window, then the most-recently-registered window.
    func defaultEntry() -> Entry? {
        if let key = NSApplication.shared.keyWindow,
           let entry = entries.values.first(where: { $0.window === key }) {
            return entry
        }
        if let main = NSApplication.shared.mainWindow,
           let entry = entries.values.first(where: { $0.window === main }) {
            return entry
        }
        for id in registrationOrder.reversed() {
            if let entry = entries[id], entry.window != nil {
                return entry
            }
        }
        return registrationOrder.last.flatMap { entries[$0] }
    }

    /// Resolve `(windowId?, tabId?)` to a registry entry, applying the same
    /// rules as the HTTP handlers:
    ///
    /// - Explicit `windowId`: must exist; otherwise `nil` (caller surfaces
    ///   `WINDOW_NOT_FOUND`).
    /// - Explicit `tabId` without `windowId`: locate the window that owns the
    ///   tab; fall back to the default window if no tab matches (caller will
    ///   surface `TAB_NOT_FOUND` after attempting tab resolution).
    /// - Neither specified: the default window.
    func resolveEntry(windowId: String?, tabId: String?) -> Entry? {
        if let windowId {
            return entries[windowId]
        }
        if let tabId, let uuid = UUID(uuidString: tabId),
           let entry = entry(containingTabId: uuid) {
            return entry
        }
        return defaultEntry()
    }

    /// Snapshot of every registered window, ordered by registration time
    /// (oldest first). Dead weak references are excluded.
    func allEntries() -> [Entry] {
        registrationOrder.compactMap { entries[$0] }.filter { $0.window != nil }
    }
}

/// Hidden bridge view that captures the hosting `NSWindow` after SwiftUI
/// attaches it and forwards the live reference to `WindowRegistry`. We
/// cannot read the actual window from `.onAppear` because the SwiftUI view
/// is hosted inside an `NSHostingView` whose `.window` is only populated
/// after the view enters the AppKit view hierarchy.
struct WindowRegistrationBridge: NSViewRepresentable {
    let windowId: String
    let tabStore: TabStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let id = windowId
        let store = tabStore
        DispatchQueue.main.async {
            WindowRegistry.shared.register(id: id, window: nsView.window, tabStore: store)
        }
    }
}
