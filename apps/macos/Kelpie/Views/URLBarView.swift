import SwiftUI

/// Reference-style navigation row. Developer tools live in the trailing popup.
struct URLBarView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var rendererState: RendererState
    @ObservedObject var viewportState: ViewportState
    @ObservedObject var aiState: AIState
    let isAIPanelOpen: Bool
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onHome: () -> Void
    let isStartPage: Bool
    let onAIToggle: () -> Void
    let onSnapshot3D: () -> Void
    let is3DActive: Bool
    let show3DControls: Bool
    let inspectorMode: String
    let onSetInspectorMode: (String) -> Void
    let onInspectorExit: () -> Void
    let onInspectorZoomIn: () -> Void
    let onInspectorZoomOut: () -> Void
    let onInspectorReset: () -> Void
    let onSwitchRenderer: (RendererState.Engine) -> Void
    let onSafariAuth: () -> Void
    let onBookmarks: () -> Void
    let onHistory: () -> Void
    let onNetworkInspector: () -> Void
    let onSettings: () -> Void

    @ObservedObject var bookmarkStore = BookmarkStore.shared
    @State var showTools = false
    @State private var urlText = ""
    @FocusState private var isAddressFieldFocused: Bool

    var pageURL: URL? {
        guard !isStartPage, let url = URL(string: browserState.currentURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private var isSecurePage: Bool { pageURL?.scheme?.lowercased() == "https" }
    private var isBookmarked: Bool { bookmarkStore.bookmarks.contains { $0.url == pageURL?.absoluteString } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AppKitToolbarButton(
                    systemName: "arrow.left",
                    accessibilityID: "browser.nav.back",
                    accessibilityLabel: "Back",
                    isEnabled: browserState.canGoBack,
                    action: onBack
                )
                AppKitToolbarButton(
                    systemName: "arrow.right",
                    accessibilityID: "browser.nav.forward",
                    accessibilityLabel: "Forward",
                    isEnabled: browserState.canGoForward,
                    action: onForward
                )
                AppKitToolbarButton(
                    systemName: "arrow.clockwise",
                    accessibilityID: "browser.nav.reload",
                    accessibilityLabel: "Reload",
                    action: onReload
                )
                AppKitToolbarButton(
                    systemName: "house",
                    accessibilityID: "browser.nav.home",
                    accessibilityLabel: "Home",
                    action: onHome
                )
                addressField.layoutPriority(1)
                AppKitToolbarButton(
                    systemName: "clock",
                    accessibilityID: "browser.action.history",
                    accessibilityLabel: "History",
                    action: onHistory
                )
                AppKitToolbarButton(
                    systemName: "ellipsis.vertical",
                    accessibilityID: "browser.action.more",
                    accessibilityLabel: "More browser controls",
                    isSelected: showTools
                ) {
                    showTools.toggle()
                }
                .popover(isPresented: $showTools, arrowEdge: .bottom) { toolsPopup }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            FavouritesBarView(onNavigate: onNavigate, onAddBookmark: addBookmark, canAddBookmark: pageURL != nil && !isBookmarked)
        }
        .background(BrowserGlassBackground())
        .overlay(alignment: .bottom) { BrowserChromeStyle.separator.frame(height: 1) }
        .onAppear { syncAddress() }
        .onChange(of: browserState.currentURL) { _, _ in if !isAddressFieldFocused || urlText.isEmpty { syncAddress() } }
        .onChange(of: isStartPage) { _, _ in syncAddress() }
    }

    private func syncAddress() { urlText = isStartPage ? "" : browserState.currentURL }

    private func addBookmark() {
        guard let pageURL, !isBookmarked else { return }
        bookmarkStore.add(title: browserState.pageTitle.isEmpty ? pageURL.absoluteString : browserState.pageTitle,
                          url: pageURL.absoluteString)
    }

    private var toolsPopup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Browser controls").font(.headline)
                popupAction("Bookmarks", icon: "bookmark", id: "bookmarks", action: onBookmarks)
                popupAction("Safari authentication", icon: "safari", id: "safari-auth", enabled: pageURL != nil, action: onSafariAuth)
                popupAction("Network inspector", icon: "antenna.radiowaves.left.and.right", id: "network", action: onNetworkInspector)
                popupAction("Settings", icon: "gearshape", id: "settings", action: onSettings)
                if aiState.isAvailable {
                    popupAction(isAIPanelOpen ? "Hide AI assistant" : "AI assistant", icon: "sparkles", id: "ai", action: onAIToggle)
                }
                if rendererState.activeEngine != .chromium {
                    popupAction(is3DActive ? "Exit 3D inspector" : "3D inspector", icon: "cube.transparent", id: "snapshot3d", action: onSnapshot3D)
                }
                Divider()
                Text("Viewport · \(viewportState.resolutionLabel)").font(.subheadline).foregroundStyle(.secondary)
                selectorsRow
            }
            .padding(18)
        }
        .frame(width: 320, height: 420)
    }

    private func popupAction(_ title: String, icon: String, id: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 20)
            Text(title)
            Spacer()
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .overlay(AppKitInvisibleButton(
                    accessibilityID: "browser.action.\(id)",
                    accessibilityLabel: title,
                    isEnabled: enabled) {
            showTools = false
            action(
                )
        })
        .opacity(enabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: isSecurePage ? "lock.fill" : "globe")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isSecurePage ? Color.green : BrowserChromeStyle.muted)

            ZStack(alignment: .leading) {
                if let suffix = inlineCompletionSuffix {
                    HStack(spacing: 0) {
                        Text(verbatim: urlText)
                            .hidden()
                        Text(verbatim: suffix)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .allowsHitTesting(false)
                }

                TextField("Search or enter website name", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .focused($isAddressFieldFocused)
                    .accessibilityIdentifier("browser.address")
                    .onSubmit { navigate() }
            }
            AppKitToolbarButton(
                    systemName: isBookmarked ? "star.fill" : "star",
                    accessibilityID: "browser.action.bookmark-current",
                    accessibilityLabel: isBookmarked ? "Page bookmarked" : "Bookmark this page",
                    isEnabled: pageURL != nil && !isBookmarked,
                    action: addBookmark
                )
            PageShareButton(url: pageURL)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BrowserChromeStyle.address)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BrowserChromeStyle.separator, lineWidth: 0.5)
        )
    }

    private func navigate() {
        var url = resolvedNavigationText()
        if !startsWithScheme(url) {
            url = "https://\(url)"
        }
        isAddressFieldFocused = false
        onNavigate(url)
    }

    private var inlineCompletionSuffix: String? {
        let trimmedInput = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAddressFieldFocused,
              let display = inlineCompletionDisplay(for: trimmedInput),
              display.count > trimmedInput.count
        else {
            return nil
        }
        return String(display.dropFirst(trimmedInput.count))
    }

    private func resolvedNavigationText() -> String {
        let trimmedInput = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return trimmedInput }
        return HistoryStore.shared.bestURLCompletion(for: trimmedInput) ?? trimmedInput
    }

    private func inlineCompletionDisplay(for input: String) -> String? {
        guard !input.isEmpty,
              let fullCompletion = HistoryStore.shared.bestURLCompletion(for: input)
        else {
            return nil
        }

        return completionDisplayCandidates(for: fullCompletion, input: input)
            .first { candidate in
                candidate.count > input.count &&
                    candidate.lowercased().hasPrefix(input.lowercased())
            }
    }

    private func completionDisplayCandidates(for fullCompletion: String, input: String) -> [String] {
        if startsWithScheme(input) {
            return [fullCompletion]
        }

        let withoutScheme = stripScheme(from: fullCompletion)
        let withoutWww = stripLeadingWww(from: withoutScheme)
        return [withoutWww, withoutScheme, fullCompletion].reduce(into: [String]()) { result, candidate in
            guard !result.contains(candidate) else { return }
            result.append(candidate)
        }
    }

    private func startsWithScheme(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    private func stripScheme(from value: String) -> String {
        guard let range = value.range(of: "://") else { return value }
        return String(value[range.upperBound...])
    }

    private func stripLeadingWww(from value: String) -> String {
        value.lowercased().hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }
}
