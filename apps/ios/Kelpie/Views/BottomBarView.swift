import SwiftUI

/// One native bottom surface; tabs have their own top strip or overview.
struct BottomBarView<MoreContent: View>: View {
    @ObservedObject var tabStore: TabStore
    @ObservedObject var browserState: BrowserState
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onBookmarks: () -> Void
    let onShowTabs: () -> Void
    @Binding var isCollapsed: Bool
    @Binding var isEditing: Bool
    @ViewBuilder let moreContent: () -> MoreContent

    @State private var urlText = ""
    @FocusState private var addressFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 600
            let compact = isCollapsed && !isEditing
            let showShare = geometry.size.width >= 390
            let spacing: CGFloat = wide ? 14 : 5
            let padding: CGFloat = wide ? 20 : 8
            let left = addressFocused ? padding : padding + 88 + spacing * 2
            let right = padding + trailingWidth(wide: wide, showShare: showShare, spacing: spacing) + spacing
            let available = max(100, geometry.size.width - left - right)
            ZStack {
                expandedControls(wide: wide, showShare: showShare)
                    .opacity(compact ? 0 : 1)
                    .allowsHitTesting(!compact)
                    .accessibilityHidden(compact)
                // This is the same address surface in both states. Only its bounds
                // and center move; no insertion, removal or matched-view crossfade.
                addressField(compact: compact)
                    .frame(width: compact ? min(180, available * 0.85) : min(available, wide ? 620 : available))
                    .position(
                        x: compact ? geometry.size.width / 2 : left + available / 2,
                        y: compact ? 17 : 31
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: isCollapsed && !isEditing ? 34 : 62)
        .background {
            UnevenChromeBackground()
                .opacity(isCollapsed && !isEditing ? 0 : 1)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isCollapsed)
        .onAppear { urlText = browserState.currentURL }
        .onChange(of: browserState.currentURL) { value in
            if !addressFocused { urlText = value }
        }
        .onChange(of: addressFocused) { focused in
            isEditing = focused
            if focused { isCollapsed = false }
        }
        .onChange(of: tabStore.activeBrowserTabID) { _ in
            addressFocused = false
            isCollapsed = false
        }
    }

    private func expandedControls(wide: Bool, showShare: Bool) -> some View {
        HStack(spacing: wide ? 14 : 5) {
            if !addressFocused {
                BrowserChromeButton(symbol: "chevron.left", label: "Back", identifier: "browser.nav.back", enabled: browserState.canGoBack, action: onBack)
                BrowserChromeButton(symbol: "chevron.right", label: "Forward", identifier: "browser.nav.forward", enabled: browserState.canGoForward, action: onForward)
            }
            Spacer(minLength: 0)
            if addressFocused {
                Button("Cancel") {
                    addressFocused = false
                    urlText = browserState.currentURL
                }
                .frame(width: 64, height: 44)
            } else {
                if showShare, let url = URL(string: browserState.currentURL), url.scheme != nil {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 19))
                            .frame(width: 44, height: 44)
                            .modifier(BrowserGlass())
                    }
                    .accessibilityLabel("Share page")
                }
                if wide || showShare {
                    BrowserChromeButton(symbol: "book", label: "Bookmarks", identifier: "browser.bookmarks", action: onBookmarks)
                }
                Menu {
                    Button("Tabs (\(tabStore.tabs.count))", systemImage: "square.on.square", action: onShowTabs)
                        .accessibilityIdentifier("browser.tabs.count")
                    Button("New tab", systemImage: "plus") { tabStore.addBrowserTab() }
                        .accessibilityIdentifier("browser.tabs.add")
                    Button("Bookmarks", systemImage: "book", action: onBookmarks)
                    if let url = URL(string: browserState.currentURL) { ShareLink(item: url) }
                    Divider()
                    moreContent()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .modifier(BrowserGlass())
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("browser.more")
            }
        }
        .padding(.horizontal, wide ? 20 : 8)
        .frame(height: 44)
        .tint(.accentColor)
    }

    private func trailingWidth(wide: Bool, showShare: Bool, spacing: CGFloat) -> CGFloat {
        if addressFocused { return 64 }
        let share = showShare && URL(string: browserState.currentURL)?.scheme != nil
        let count = 1 + (wide || showShare ? 1 : 0) + (share ? 1 : 0)
        return CGFloat(count) * 44 + CGFloat(count - 1) * spacing
    }

    private var displayedAddress: Binding<String> {
        Binding(
            get: { addressFocused ? urlText : (browserState.currentURL.isEmpty ? "" : browserDomain(browserState.currentURL)) },
            set: { urlText = $0 }
        )
    }

    private func addressField(compact: Bool) -> some View {
        HStack(spacing: compact ? 0 : 5) {
            if !addressFocused {
                Image(systemName: browserState.currentURL.hasPrefix("https:") ? "lock.fill" : "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: compact ? 0 : 12)
                    .opacity(compact ? 0 : 1)
            }
            TextField("Search or enter address", text: displayedAddress)
                .font(.system(size: 14))
                .scaleEffect(compact ? 12.0 / 14.0 : 1)
                .multilineTextAlignment(addressFocused ? .leading : .center)
                .allowsHitTesting(!compact)
                .accessibilityHidden(compact)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($addressFocused)
                .accessibilityIdentifier("browser.url.field")
                .onSubmit(navigate)
            if !addressFocused {
                Button(action: onReload) {
                    Image(systemName: browserState.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 17))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(browserState.isLoading ? "Stop loading" : "Reload")
                .accessibilityIdentifier("browser.nav.reload")
                .frame(width: compact ? 0 : 36)
                .opacity(compact ? 0 : 1)
                .allowsHitTesting(!compact)
                .accessibilityHidden(compact)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, compact || addressFocused ? 12 : 0)
        .frame(height: compact ? 28 : 44)
        .modifier(BrowserGlass())
        .overlay {
            if compact {
                Button { isCollapsed = false } label: {
                    Color.clear.frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand address bar, \(browserDomain(browserState.currentURL))")
                .accessibilityIdentifier("browser.bottom-bar.collapsed")
                .transition(.identity)
            }
        }
        .overlay {
            DirectionalBrowserDrag(axis: .upward, enabled: !addressFocused, onChange: { _ in }, onEnd: { distance, speed in
                if distance < -32 || (distance < -12 && speed < -450) { onShowTabs() }
            })
        }
        .accessibilityAction(named: "Show tabs", onShowTabs)
    }

    private func navigate() {
        var value = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !value.contains("://") { value = "https://\(value)" }
        addressFocused = false
        onNavigate(value)
    }
}

private struct UnevenChromeBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.45), lineWidth: 0.75)
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
