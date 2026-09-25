import SwiftUI

/// Tabs stay at the top of every iPad window, including narrow multitasking widths.
struct TabletTabStrip: View {
    @ObservedObject var tabStore: TabStore
    @ObservedObject var appearance: BrowserChromeAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(tabStore.tabs) { tab in
                                TabletBrowserTab(
                                    tab: tab,
                                    selected: tab.id == tabStore.activeBrowserTabID,
                                    palette: appearance.palette,
                                    onSelect: { tabStore.selectBrowserTab(id: tab.id) },
                                    onClose: { tabStore.closeBrowserTab(id: tab.id) }
                                )
                                .id(tab.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 48, alignment: .bottom)
                    }
                    .frame(width: min(CGFloat(tabStore.tabs.count) * 213 + 16, max(0, geometry.size.width - 64)))
                    Button { tabStore.addBrowserTab() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 21))
                            .frame(width: 44, height: 44)
                            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New tab")
                    .accessibilityValue("\(tabStore.tabs.count) tabs")
                    .accessibilityIdentifier("browser.tabs.add")
                    .padding(.trailing, 8)
                    Spacer(minLength: 0)
                }
                .frame(height: 48)
                .foregroundStyle(Color(uiColor: .label))
                .background(Color(uiColor: .systemGray5).ignoresSafeArea(edges: .top))
                .onAppear {
                    proxy.scrollTo(tabStore.activeBrowserTabID, anchor: .center)
                }
                .onChange(of: tabStore.activeBrowserTabID) { identifier in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        proxy.scrollTo(identifier, anchor: .center)
                    }
                }
            }
            .frame(height: 48)
        }
    }
}

private struct TabletBrowserTab: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let palette: BrowserChromePalette
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                BrowserTabLabel(tab: tab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("browser.tabs.select.\(tab.id)")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(tab.pageTitle.isEmpty ? "tab" : tab.pageTitle)")
            .accessibilityIdentifier("browser.tabs.close.\(tab.id)")
        }
        .frame(width: 210, height: 44)
        .foregroundStyle(Color(uiColor: selected ? palette.foreground.color : .secondaryLabel))
        .background(Color(uiColor: selected ? palette.background.color : .systemGray6), in: BrowserTabShape())
        .overlay { BrowserTabShape().stroke(.white.opacity(selected ? 0.5 : 0.25), lineWidth: 0.75) }
    }
}

/// Curved shoulders meet the page flush instead of forming floating pills.
private struct BrowserTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let width = rect.width, height = rect.height
            path.move(to: CGPoint(x: 0, y: height))
            path.addCurve(to: CGPoint(x: 10, y: 14), control1: CGPoint(x: 8, y: height), control2: CGPoint(x: 7, y: 24))
            path.addQuadCurve(to: CGPoint(x: 25, y: 0), control: CGPoint(x: 12, y: 0))
            path.addLine(to: CGPoint(x: width - 25, y: 0))
            path.addQuadCurve(to: CGPoint(x: width - 10, y: 14), control: CGPoint(x: width - 12, y: 0))
            path.addCurve(to: CGPoint(x: width, y: height), control1: CGPoint(x: width - 7, y: 24), control2: CGPoint(x: width - 8, y: height))
        }
    }
}
