# Safari-Style Tab Bar — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Safari-style pill tab bar above the renderer — pills spread to fill available width, scroll when dense, with a sliding active indicator, per-tab favicons (or letter avatars), and full per-tab navigation state.

**Architecture:** Each tab owns a `WKWebViewRenderer` (independent WKWebView with history). `TabStore` is a `@StateObject` in `BrowserView`; when the active tab changes, `BrowserView` updates `serverState.handlerContext.renderer` so all existing handlers continue to work without modification. CEF remains a single shared renderer; tab switching while CEF is active navigates CEF to the new tab's URL. The tab bar is fully AppKit-backed (NSViewRepresentable) per the AGENTS.md WebView-in-window rule.

**Tech Stack:** Swift/SwiftUI/AppKit, WKWebView, `NSScrollView` for overflow, `NSAnimationContext` for active indicator slide.

---

## Task 1 — Tab model and store

**Files:**
- Create: `apps/macos/Kelpie/Browser/TabStore.swift`
- Modify: `apps/macos/Kelpie/Network/ServerState.swift`

### Step 1: Write failing test

```swift
// In a test target (or manual verification — no existing test target for tabs)
// These are unit tests you can add to verify TabStore behaviour.
// Create: apps/macos/KelpieTests/TabStoreTests.swift (if test target exists; skip if not)

func testAddTabIncrementsCount() {
    let store = TabStore()
    XCTAssertEqual(store.tabs.count, 1)   // initial tab
    store.addTab()
    XCTAssertEqual(store.tabs.count, 2)
}

func testCloseTabRemovesCorrectTab() {
    let store = TabStore()
    let second = store.addTab()
    store.closeTab(id: second.id)
    XCTAssertEqual(store.tabs.count, 1)
}

func testCloseLastTabCreatesNewOne() {
    let store = TabStore()
    let first = store.tabs[0]
    store.closeTab(id: first.id)
    XCTAssertEqual(store.tabs.count, 1)
    XCTAssertNotEqual(store.tabs[0].id, first.id)
}

func testSelectTabUpdatesActiveID() {
    let store = TabStore()
    let second = store.addTab()
    store.selectTab(id: second.id)
    XCTAssertEqual(store.activeTabID, second.id)
}
```

### Step 2: Write `TabStore.swift`

```swift
import Foundation
import AppKit

/// Per-tab browser state surfaced to the tab bar.
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let renderer: WKWebViewRenderer

    @Published var title: String = "New Tab"
    @Published var currentURL: String = ""
    @Published var isLoading: Bool = false
    @Published var favicon: NSImage? = nil

    init() {
        self.renderer = WKWebViewRenderer()
        // renderer.onStateChange connected by TabStore after init so the
        // closure can weakly capture the store.
    }
}

@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabID: UUID?

    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }

    init() {
        let initial = Tab()
        tabs = [initial]
        activeTabID = initial.id
        bind(initial)
    }

    @discardableResult
    func addTab() -> Tab {
        let tab = Tab()
        bind(tab)
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        if tabs.count == 1 {
            // Replace last tab rather than leaving an empty strip.
            let replacement = Tab()
            bind(replacement)
            tabs = [replacement]
            activeTabID = replacement.id
            return
        }

        tabs.remove(at: idx)
        if activeTabID == id {
            let newIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[newIdx].id
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    private func bind(_ tab: Tab) {
        tab.renderer.onStateChange = { [weak tab] in
            guard let tab else { return }
            tab.title = tab.renderer.currentTitle.isEmpty ? "New Tab" : tab.renderer.currentTitle
            tab.currentURL = tab.renderer.currentURL?.absoluteString ?? ""
            tab.isLoading = tab.renderer.isLoading
        }
    }
}
```

### Step 3: Add `setActiveWebKitRenderer` to `ServerState`

In `apps/macos/Kelpie/Network/ServerState.swift`, change:
```swift
private(set) var wkRenderer: WKWebViewRenderer?
```
to:
```swift
var wkRenderer: WKWebViewRenderer?
```

Add a method just below the property:
```swift
/// Called by BrowserView when the active tab changes so the tab's renderer
/// becomes the target for all handlers.
func setActiveWebKitRenderer(_ renderer: WKWebViewRenderer) {
    renderer.onScriptMessage = { [weak self] name, body in
        self?.handlerContext.handleScriptMessage(name: name, body: body)
    }
    wkRenderer = renderer
    handlerContext.renderer = renderer
}
```

### Step 4: Verify

Build the project. No regressions; single-tab behaviour identical to before. `TabStore` is not yet wired to anything, so you won't see tabs yet.

### Step 5: Commit

```bash
git add apps/macos/Kelpie/Browser/TabStore.swift \
        apps/macos/Kelpie/Network/ServerState.swift
git commit -m "feat(macos/tabs): add Tab/TabStore model with per-tab WKWebViewRenderer"
```

---

## Task 2 — Tab bar view (AppKit)

**Files:**
- Create: `apps/macos/Kelpie/Views/TabBarView.swift`

This is the most visual task. Build the whole view as a single `NSViewRepresentable` that owns all AppKit subviews. No SwiftUI inside — everything is NSView/NSButton.

### Step 1: Create `TabBarView.swift`

Height: `34` pt. Background: `NSColor.windowBackgroundColor` with a 1 pt bottom separator.

Visual anatomy of one pill:
```
┌─────────────────────────────────────┐
│ [favicon/letter 14pt] [title] [×]   │
└─────────────────────────────────────┘
```

Active indicator: a `CAShapeLayer` (rounded rect) that sits below the pills and slides with `CABasicAnimation`.

Spreading math (called any time tab count or bar width changes):
```
let add   = 28.0            // width of the "+" button on the right
let gap   = 6.0             // padding from the right edge
let avail = bar.frame.width - add - gap - 4   // 4 pt left inset
let ideal = avail / Double(tabs.count)
let w     = min(200, max(80, ideal))
// If w * numTabs <= avail: tabs spread (content fits)
// Otherwise: scroll kicks in
```

```swift
import SwiftUI
import AppKit

struct TabBarView: NSViewRepresentable {
    @ObservedObject var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSelectTab: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNewTab: onNewTab, onCloseTab: onCloseTab, onSelectTab: onSelectTab)
    }

    func makeNSView(context: Context) -> TabBarContainerView {
        let view = TabBarContainerView()
        context.coordinator.install(in: view, tabStore: tabStore)
        return view
    }

    func updateNSView(_ nsView: TabBarContainerView, context: Context) {
        context.coordinator.update(in: nsView, tabStore: tabStore)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var onNewTab: () -> Void
        var onCloseTab: (UUID) -> Void
        var onSelectTab: (UUID) -> Void

        private weak var container: TabBarContainerView?
        private var pillsByID: [UUID: TabPillView] = [:]
        private var cancellables: [UUID: [NSKeyValueObservation]] = [:]

        init(
            onNewTab: @escaping () -> Void,
            onCloseTab: @escaping (UUID) -> Void,
            onSelectTab: @escaping (UUID) -> Void
        ) {
            self.onNewTab = onNewTab
            self.onCloseTab = onCloseTab
            self.onSelectTab = onSelectTab
        }

        func install(in container: TabBarContainerView, tabStore: TabStore) {
            self.container = container
            container.addButton.target = self
            container.addButton.action = #selector(handleAdd)
            rebuild(in: container, tabStore: tabStore)
        }

        func update(in container: TabBarContainerView, tabStore: TabStore) {
            let existing = Set(pillsByID.keys)
            let current  = Set(tabStore.tabs.map(\.id))

            // Add new pills
            for tab in tabStore.tabs where !existing.contains(tab.id) {
                let pill = TabPillView(tab: tab)
                pill.onSelect = { [weak self] id in self?.onSelectTab(id) }
                pill.onClose  = { [weak self] id in self?.onCloseTab(id) }
                container.scrollContent.addSubview(pill)
                pillsByID[tab.id] = pill
            }

            // Remove closed pills
            for id in existing.subtracting(current) {
                pillsByID[id]?.removeFromSuperview()
                pillsByID.removeValue(forKey: id)
            }

            relayout(in: container, tabStore: tabStore)
        }

        private func rebuild(in container: TabBarContainerView, tabStore: TabStore) {
            pillsByID.values.forEach { $0.removeFromSuperview() }
            pillsByID.removeAll()
            for tab in tabStore.tabs {
                let pill = TabPillView(tab: tab)
                pill.onSelect = { [weak self] id in self?.onSelectTab(id) }
                pill.onClose  = { [weak self] id in self?.onCloseTab(id) }
                container.scrollContent.addSubview(pill)
                pillsByID[tab.id] = pill
            }
            relayout(in: container, tabStore: tabStore)
        }

        private func relayout(in container: TabBarContainerView, tabStore: TabStore) {
            let tabs = tabStore.tabs
            guard !tabs.isEmpty else { return }

            let addW:   CGFloat = 28
            let gap:    CGFloat = 4
            let rightM: CGFloat = 6
            let avail = container.frame.width - addW - rightM - gap
            let ideal = avail / CGFloat(tabs.count)
            let tabW  = min(200, max(80, ideal))
            let totalTabsW = tabW * CGFloat(tabs.count)
            let contentW = max(totalTabsW + addW + rightM + gap, container.frame.width)

            container.scrollContent.frame = CGRect(
                x: 0, y: 0, width: contentW, height: container.frame.height
            )
            container.scrollView.documentView?.frame = container.scrollContent.frame

            let pillH: CGFloat = 26
            let pillY: CGFloat = (container.frame.height - pillH) / 2

            for (i, tab) in tabs.enumerated() {
                let x = CGFloat(i) * tabW + gap / 2
                pillsByID[tab.id]?.frame = CGRect(x: x, y: pillY, width: tabW - 2, height: pillH)
                pillsByID[tab.id]?.isActive = tab.id == tabStore.activeTabID
                pillsByID[tab.id]?.refreshContent()
            }

            // Add button
            container.addButton.frame = CGRect(
                x: totalTabsW + gap / 2,
                y: (container.frame.height - 26) / 2,
                width: 26,
                height: 26
            )

            // Slide active indicator
            if let activeID = tabStore.activeTabID,
               let pill = pillsByID[activeID] {
                moveIndicator(in: container, to: pill.frame)
            }
        }

        private func moveIndicator(in container: TabBarContainerView, to frame: CGRect) {
            let inset: CGFloat = 2
            let target = frame.insetBy(dx: inset, dy: inset)
            let layer = container.indicatorLayer

            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = layer.path
            anim.duration  = 0.22
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let newPath = CGPath(
                roundedRect: target,
                cornerWidth: 8,
                cornerHeight: 8,
                transform: nil
            )
            layer.path = newPath
            layer.add(anim, forKey: "slide")
        }

        @objc private func handleAdd() { onNewTab() }
    }
}

// MARK: - Container view

final class TabBarContainerView: NSView {
    let scrollView    = NSScrollView()
    let scrollContent = NSView()
    let addButton     = NSButton()
    let indicatorLayer = CAShapeLayer()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Bottom border
        let border = CALayer()
        border.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        border.frame = CGRect(x: 0, y: frame.height - 1, width: frame.width, height: 1)
        border.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(border)

        // Active indicator layer (behind pills)
        indicatorLayer.fillColor = NSColor.selectedControlColor.withAlphaComponent(0.18).cgColor
        indicatorLayer.strokeColor = NSColor.selectedControlColor.withAlphaComponent(0.35).cgColor
        indicatorLayer.lineWidth = 1
        layer?.addSublayer(indicatorLayer)

        // Scroll view
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller   = false
        scrollView.drawsBackground       = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollContent.wantsLayer = true
        scrollContent.layer?.backgroundColor = .clear
        scrollView.documentView = scrollContent
        addSubview(scrollView)

        // Add tab button
        addButton.isBordered       = false
        addButton.setButtonType(.momentaryPushIn)
        addButton.imagePosition    = .imageOnly
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        addButton.contentTintColor = .secondaryLabelColor
        addButton.wantsLayer       = true
        addButton.layer?.cornerRadius = 5
        addButton.setAccessibilityIdentifier("browser.tabs.add")
        addSubview(addButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layout() {
        super.layout()
        // Re-layout is triggered by Coordinator.update via updateNSView
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Individual pill

final class TabPillView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onClose:  ((UUID) -> Void)?

    private let tab: Tab
    private let faviconView   = NSImageView()
    private let letterView    = LetterAvatarView()
    private let titleField    = NSTextField(labelWithString: "")
    private let closeButton   = NSButton()
    private var kvoTitle:     NSKeyValueObservation?
    private var kvoFavicon:   NSKeyValueObservation?
    private var kvoLoading:   NSKeyValueObservation?

    var isActive: Bool = false {
        didSet { updateAppearance() }
    }

    override var isFlipped: Bool { true }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        // Favicon / letter avatar
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        letterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(letterView)
        addSubview(faviconView)

        // Title
        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: 11, weight: .regular)
        titleField.textColor = .labelColor
        titleField.drawsBackground = false
        titleField.isBordered = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        // Close button
        closeButton.isBordered    = false
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold))
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 4
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.setAccessibilityIdentifier("browser.tabs.\(tab.id).close")
        addSubview(closeButton)

        let iconSize: CGFloat = 14
        let closeSize: CGFloat = 16
        let iconLeft: CGFloat = 8
        let titleLeft: CGFloat = iconLeft + iconSize + 4
        let closeRight: CGFloat = 6

        NSLayoutConstraint.activate([
            // Favicon / letter
            faviconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: iconLeft),
            faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: iconSize),
            faviconView.heightAnchor.constraint(equalToConstant: iconSize),

            letterView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: iconLeft),
            letterView.centerYAnchor.constraint(equalTo: centerYAnchor),
            letterView.widthAnchor.constraint(equalToConstant: iconSize),
            letterView.heightAnchor.constraint(equalToConstant: iconSize),

            // Close button
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -closeRight),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: closeSize),
            closeButton.heightAnchor.constraint(equalToConstant: closeSize),

            // Title — fills space between icon and close button
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: titleLeft),
            titleField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Observe tab published properties
        kvoTitle = tab.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshContent() }
        }
        kvoFavicon = tab.observe(\.favicon, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshContent() }
        }

        refreshContent()
        updateAppearance()
    }

    func refreshContent() {
        titleField.stringValue = tab.title

        if let favicon = tab.favicon {
            faviconView.image = favicon
            faviconView.isHidden = false
            letterView.isHidden  = true
        } else {
            faviconView.isHidden = true
            letterView.isHidden  = false
            letterView.setDomain(tab.currentURL)
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = isActive
            ? NSColor.selectedControlColor.withAlphaComponent(0.08).cgColor
            : .clear
    }

    override func mouseDown(with event: NSEvent) {
        // Only trigger select if the click isn't in the close button
        let pt = convert(event.locationInWindow, from: nil)
        if !closeButton.frame.contains(pt) {
            onSelect?(tab.id)
        }
    }

    @objc private func handleClose() {
        onClose?(tab.id)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Letter avatar

/// Renders the first letter of a domain in a tinted rounded-rect.
final class LetterAvatarView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var domainLetter: String = "?"

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        label.font = .boldSystemFont(ofSize: 9)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func setDomain(_ urlString: String) {
        let host = URL(string: urlString)?.host ?? urlString
        let letter = host.first.map { String($0).uppercased() } ?? "?"
        domainLetter = letter
        label.stringValue = letter
        layer?.backgroundColor = colorForDomain(host).cgColor
    }

    private func colorForDomain(_ domain: String) -> NSColor {
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.40, green: 0.56, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.55, green: 0.75, blue: 0.55, alpha: 1),
            NSColor(calibratedRed: 0.85, green: 0.55, blue: 0.40, alpha: 1),
            NSColor(calibratedRed: 0.70, green: 0.50, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.35, alpha: 1),
            NSColor(calibratedRed: 0.50, green: 0.75, blue: 0.80, alpha: 1),
        ]
        let hash = domain.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    required init?(coder: NSCoder) { fatalError() }
}
```

### Step 2: Build and check

Build. Fix any compile errors. At this point the view exists but isn't placed in BrowserView yet.

### Step 3: Commit

```bash
git add apps/macos/Kelpie/Views/TabBarView.swift
git commit -m "feat(macos/tabs): add AppKit-backed TabBarView with pill spreading and active indicator"
```

---

## Task 3 — Wire BrowserView

**Files:**
- Modify: `apps/macos/Kelpie/Views/BrowserView.swift`

### Step 1: Add TabStore and insert TabBarView

In the `BrowserView` struct, add:

```swift
@StateObject private var tabStore = TabStore()
```

In `body`, inside the outer `VStack(spacing: 0)`, insert `TabBarView` **between** `URLBarView(...)` and `HStack(spacing: 0)`:

```swift
TabBarView(
    tabStore: tabStore,
    onNewTab: { tabStore.addTab(); connectNewTab(tabStore.activeTab!) },
    onCloseTab: { id in
        let wasActive = tabStore.activeTabID == id
        tabStore.closeTab(id: id)
        if wasActive { activateTab(tabStore.activeTab!) }
    },
    onSelectTab: { id in
        tabStore.selectTab(id: id)
        activateTab(tabStore.activeTab!)
    }
)
.frame(height: 34)
```

### Step 2: Add `connectNewTab` and `activateTab` helpers

Add these private methods to `BrowserView`:

```swift
private func connectNewTab(_ tab: Tab) {
    serverState.setActiveWebKitRenderer(tab.renderer)
    sync(browserState: browserState, from: tab.renderer)
    // Renderer's onStateChange already set in TabStore.bind(_:)
    // Also hook it to update browserState (the shared URL bar state)
    tab.renderer.onStateChange = { [weak tab, weak browserState,
                                    weak handlerContext = serverState.handlerContext] in
        guard let tab, let browserState,
              let renderer = handlerContext?.renderer,
              // Only update shared browserState when this tab is still active.
              renderer === tab.renderer else { return }
        Task { @MainActor in
            // Keep tab's own properties updated
            tab.title = tab.renderer.currentTitle.isEmpty ? "New Tab" : tab.renderer.currentTitle
            tab.currentURL = tab.renderer.currentURL?.absoluteString ?? ""
            tab.isLoading  = tab.renderer.isLoading
            // Update shared bar
            sync(browserState: browserState, from: tab.renderer)
            // Favicon extraction on load complete
            if !tab.renderer.isLoading {
                FaviconExtractor.extract(from: tab.renderer) { image in
                    tab.favicon = image
                }
            }
        }
    }
}

private func activateTab(_ tab: Tab) {
    serverState.setActiveWebKitRenderer(tab.renderer)
    sync(browserState: browserState, from: tab.renderer)
    connectNewTab(tab)   // reconnects onStateChange for the new active tab
}
```

### Step 3: Wire initial tab on appear

In `BrowserView.onAppear`, BEFORE the existing Task block, add:

```swift
// Adopt the initial tab's renderer so ServerState uses it from the start.
connectNewTab(tabStore.tabs[0])
```

This must run before `serverState.startHTTPServer()` is called (which happens in the WindowGroup's `onAppear` — children fire first, so this ordering is guaranteed).

### Step 4: Update `RendererContainerView` call site

In `BrowserView.rendererSurface`, change:

```swift
RendererContainerView(serverState: serverState, rendererState: rendererState)
```
to:
```swift
RendererContainerView(serverState: serverState, rendererState: rendererState, tabStore: tabStore)
```

### Step 5: Add Cmd+T and Cmd+W

In `KelpieApp.swift`, inside `BrowserCommands.body`, add to the `CommandGroup(after: .newItem)`:

```swift
Button("New Tab") {
    NotificationCenter.default.post(name: .newTab, object: nil)
}
.keyboardShortcut("t", modifiers: .command)

Button("Close Tab") {
    NotificationCenter.default.post(name: .closeTab, object: nil)
}
.keyboardShortcut("w", modifiers: .command)
```

And at the top of `KelpieApp.swift` (in the `Notification.Name` extension):
```swift
static let newTab   = Notification.Name("com.kelpie.browser.macos.new-tab")
static let closeTab = Notification.Name("com.kelpie.browser.macos.close-tab")
```

In `BrowserView.body`, add to the chain of `.onReceive` modifiers:
```swift
.onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
    guard NSApp.keyWindow == NSApp.mainWindow || NSApp.keyWindow?.isKeyWindow == true else { return }
    let tab = tabStore.addTab()
    connectNewTab(tab)
}
.onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
    guard let id = tabStore.activeTabID else { return }
    let wasActive = tabStore.activeTabID == id
    tabStore.closeTab(id: id)
    if wasActive, let next = tabStore.activeTab { activateTab(next) }
}
```

### Step 6: Build and verify

- Launch app: one tab shows in the bar
- Cmd+T: new tab appears
- Click a tab: URL bar updates to that tab's URL
- Cmd+W: closes the current tab

### Step 7: Commit

```bash
git add apps/macos/Kelpie/Views/BrowserView.swift \
        apps/macos/Kelpie/KelpieApp.swift
git commit -m "feat(macos/tabs): wire BrowserView to TabStore; Cmd+T/Cmd+W shortcuts"
```

---

## Task 4 — RendererContainerView: multi-tab view management

**Files:**
- Modify: `apps/macos/Kelpie/Views/BrowserView.swift` (the `RendererContainerView` struct inside it)

### Step 1: Add TabStore observation

Change `RendererContainerView`:

```swift
struct RendererContainerView: NSViewRepresentable {
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState
    @ObservedObject var tabStore: TabStore     // NEW — triggers updateNSView on tab switch
    ...
}
```

### Step 2: Clean up closed tab views

In `updateNSView`, after `attachActiveRenderer(to:coordinator:)`, add cleanup:

```swift
func updateNSView(_ container: NSView, context: Context) {
    attachActiveRenderer(to: container, coordinator: context.coordinator)
    removeClosedTabViews(from: container)
}

private func removeClosedTabViews(from container: NSView) {
    let activeRenderers = Set(tabStore.tabs.map { ObjectIdentifier($0.renderer.makeView()) })
    // Also keep the CEF view (never remove it)
    for subview in container.subviews {
        let isCEF = NSStringFromClass(type(of: subview)).contains("CEF")
        if !isCEF && !activeRenderers.contains(ObjectIdentifier(subview)) {
            subview.removeFromSuperview()
        }
    }
}
```

### Step 3: Build and verify

- Open several tabs, navigate each — views accumulate but only the active one shows
- Close a tab — its WKWebView is removed from the container hierarchy

### Step 4: Commit

```bash
git add apps/macos/Kelpie/Views/BrowserView.swift
git commit -m "feat(macos/tabs): RendererContainerView tracks TabStore; cleans up closed tab views"
```

---

## Task 5 — Favicon extraction

**Files:**
- Create: `apps/macos/Kelpie/Browser/FaviconExtractor.swift`

### Step 1: Write `FaviconExtractor`

```swift
import AppKit
import WebKit

/// Extracts a page favicon using JS, then fetches and decodes it.
/// On failure, returns nil — callers show a letter avatar instead.
enum FaviconExtractor {
    static func extract(from renderer: WKWebViewRenderer, completion: @escaping (NSImage?) -> Void) {
        Task { @MainActor in
            guard let urlString = try? await renderer.evaluateJS(faviconScript) as? String,
                  let faviconURL = URL(string: urlString) else {
                completion(nil)
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: faviconURL)
                let image = NSImage(data: data)
                completion(image)
            } catch {
                completion(nil)
            }
        }
    }

    private static let faviconScript = """
    (function() {
        var link = document.querySelector('link[rel~="icon"]');
        if (link && link.href) return link.href;
        var apple = document.querySelector('link[rel="apple-touch-icon"]');
        if (apple && apple.href) return apple.href;
        return window.location.protocol + '//' + window.location.host + '/favicon.ico';
    })()
    """
}
```

### Step 2: Verify favicon loading

Navigate to a page with a favicon (e.g., `https://github.com`). The tab pill should show the GitHub favicon. Navigate to a page without one — the letter avatar should appear (coloured square with first letter of domain).

### Step 3: Commit

```bash
git add apps/macos/Kelpie/Browser/FaviconExtractor.swift
git commit -m "feat(macos/tabs): favicon extraction with letter-avatar fallback"
```

---

## Task 6 — Tab bar layout: spreading + overflow scroll

**Files:**
- Modify: `apps/macos/Kelpie/Views/TabBarView.swift`

The spreading and scroll logic is already included in Task 2's Coordinator.relayout. This task is about making it respond to window width changes.

### Step 1: React to frame changes

In `TabBarContainerView`, override `layout()`:

```swift
override func layout() {
    super.layout()
    // Notify coordinator of size change so pills re-spread.
    onFrameChange?(frame)
}
var onFrameChange: ((CGRect) -> Void)?
```

In `Coordinator.install`, after installing the add button:
```swift
container.onFrameChange = { [weak self, weak container] _ in
    guard let self, let container else { return }
    self.relayout(in: container, tabStore: self.currentTabStore!)
}
```

Store `currentTabStore` as a weak reference in Coordinator and update it in every `update` call.

### Step 2: Enable horizontal scroll when overflow

In `Coordinator.relayout`, after computing `contentW`:

```swift
let scrollNeeded = totalTabsW > avail
container.scrollView.hasHorizontalScroller = scrollNeeded
```

When scrolling to the newly-active tab on switch, add:

```swift
if let pill = pillsByID[tabStore.activeTabID ?? UUID()] {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        container.scrollView.contentView.animator().scrollToVisible(pill.frame)
    }
}
```

### Step 3: Build and verify

- Resize window to be narrow — pills compress to min 80pt, scroll indicator appears
- Widen window — pills spread to fill width
- Switch to a tab outside the visible scroll area — the bar scrolls to it

### Step 4: Commit

```bash
git add apps/macos/Kelpie/Views/TabBarView.swift
git commit -m "feat(macos/tabs): responsive pill spreading and overflow horizontal scroll"
```

---

## How to test end-to-end

1. Open Kelpie.
2. Confirm one tab in the bar with letter avatar (home URL isn't loaded yet → no favicon).
3. Navigate somewhere (e.g., `github.com`) → favicon loads.
4. Cmd+T → second tab opens, bar spreads.
5. Click first tab → URL bar switches, indicator slides.
6. Navigate second tab to `apple.com` → each tab tracks its own URL independently.
7. Narrow the window below ~480pt → pills hit min width, scroll bar appears.
8. Cmd+W → active tab closes, adjacent tab activates.
9. Close all-but-one tab, then Cmd+W on last tab → new blank tab replaces it (never zero tabs).
10. Switch to Chromium renderer → CEF view shown; tab switching navigates CEF, no crash.
