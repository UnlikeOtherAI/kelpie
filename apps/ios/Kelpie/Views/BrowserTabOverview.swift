import SwiftUI

struct BrowserTabOverview: View {
    @ObservedObject var tabStore: TabStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(tabStore.tabs.count) Tabs").font(.title2.bold())
                Spacer()
                Button("Done", action: onDismiss).frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(tabStore.tabs) { tab in
                        BrowserTabPreview(
                            tab: tab,
                            selected: tab.id == tabStore.activeBrowserTabID,
                            onSelect: { tabStore.selectBrowserTab(id: tab.id); onDismiss() },
                            onClose: { tabStore.closeBrowserTab(id: tab.id) }
                        )
                    }
                }
                .padding(16)
            }
            Button {
                tabStore.addBrowserTab()
                onDismiss()
            } label: {
                Label("New tab", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 48)
            }
            .accessibilityIdentifier("browser.tabs.add")
        }
        .background(.regularMaterial)
        .accessibilityIdentifier("browser.tabs.overview")
    }
}

private struct BrowserTabPreview: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var drag: CGFloat = 0
    @State private var closing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BrowserTabLabel(tab: tab).padding(.leading, 10)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab")
                .accessibilityIdentifier("browser.tabs.close.\(tab.id)")
            }
            Button(action: onSelect) {
                GeometryReader { geometry in
                    if let preview = tab.preview {
                        Image(uiImage: preview).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            .clipped()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: tab.isStartPage ? "star" : "globe").font(.largeTitle)
                            Text(tab.isStartPage ? "Start Page" : browserDomain(tab.currentURL))
                                .font(.caption).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .aspectRatio(0.7, contentMode: .fit)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(tab.isStartPage ? "Start Page" : browserDomain(tab.currentURL))")
            .accessibilityIdentifier("browser.tabs.select.\(tab.id)")
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(selected ? Color.accentColor : .clear, lineWidth: 3) }
        .offset(x: drag)
        .opacity(closing ? 0 : max(0.25, 1 - abs(drag) / 400))
        .overlay {
            DirectionalBrowserDrag(axis: .horizontal, enabled: !closing, onChange: { drag = $0 }, onEnd: endDrag)
        }
        .accessibilityAction(named: "Close tab", onClose)
    }

    private func endDrag(_ distance: CGFloat, _ speed: CGFloat) {
        if abs(distance) > 80 || (abs(distance) > 20 && abs(speed) > 550) {
            closing = true
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { drag = distance < 0 ? -600 : 600 }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.18), execute: onClose)
        } else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { drag = 0 }
        }
    }
}
