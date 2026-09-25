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
            Group {
                if isCollapsed && !isEditing {
                    collapsedPill
                } else {
                    expandedBar(wide: wide, showShare: geometry.size.width >= 390)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: isCollapsed && !isEditing ? 34 : 62)
        .background {
            if !isCollapsed || isEditing {
                UnevenChromeBackground()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isCollapsed)
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

    private func expandedBar(wide: Bool, showShare: Bool) -> some View {
        HStack(spacing: wide ? 14 : 5) {
            if !addressFocused {
                BrowserChromeButton(symbol: "chevron.left", label: "Back", identifier: "browser.nav.back", enabled: browserState.canGoBack, action: onBack)
                BrowserChromeButton(symbol: "chevron.right", label: "Forward", identifier: "browser.nav.forward", enabled: browserState.canGoForward, action: onForward)
            }
            if wide { Spacer(minLength: 0) }
            addressField
                .frame(maxWidth: wide ? 620 : .infinity)
            if wide { Spacer(minLength: 0) }
            if addressFocused {
                Button("Cancel") {
                    addressFocused = false
                    urlText = browserState.currentURL
                }
                .frame(minHeight: 44)
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
                if wide {
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
        .tint(.primary)
    }

    private var addressField: some View {
        HStack(spacing: 5) {
            if !addressFocused {
                Image(systemName: browserState.currentURL.hasPrefix("https:") ? "lock.fill" : "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            TextField("Search or enter address", text: $urlText)
                .font(.system(size: 14))
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
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, addressFocused ? 12 : 0)
        .frame(minWidth: 100, minHeight: 44)
        .modifier(BrowserGlass())
        .overlay {
            DirectionalBrowserDrag(axis: .upward, enabled: !addressFocused, onChange: { _ in }, onEnd: { distance, speed in
                if distance < -32 || (distance < -12 && speed < -450) { onShowTabs() }
            })
        }
        .accessibilityAction(named: "Show tabs", onShowTabs)
    }

    private var collapsedPill: some View {
        Button { isCollapsed = false } label: {
            Text(browserDomain(browserState.currentURL))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 20)
                .frame(maxWidth: 220)
                .frame(height: 28)
                .modifier(BrowserGlass())
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand address bar, \(browserDomain(browserState.currentURL))")
        .accessibilityIdentifier("browser.bottom-bar.collapsed")
        .overlay {
            DirectionalBrowserDrag(axis: .upward, onChange: { _ in }, onEnd: { distance, speed in
                if distance < -32 || (distance < -12 && speed < -450) { onShowTabs() }
            })
        }
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
