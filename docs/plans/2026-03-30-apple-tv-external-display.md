# Apple TV External Display — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When an iPhone running Kelpie connects to an Apple TV via AirPlay, display a fullscreen WKWebView on the TV that appears as a separate controllable device on the network.

**Architecture:** Listen for `UIScreen.didConnectNotification` (works iOS 15+). When an external screen connects, spin up a second `ServerState` on port 8421 with its own `BrowserState`, `HandlerContext`, `WKWebView`, and mDNS advertisement. The external display advertises as "{DeviceName} (TV)" so the CLI sees it as a distinct device. When the screen disconnects, tear everything down.

**Tech Stack:** UIKit (`UIScreen`, `UIWindow`, `UIHostingController`), SwiftUI (embedded browser view), WKWebView, Network.framework (HTTP server + mDNS)

---

### Task 1: ExternalBrowserView

Fullscreen SwiftUI view containing just a WKWebView — no URL bar, no floating menu, no welcome card. This is what renders on the Apple TV.

**Files:**
- Create: `apps/ios/Kelpie/Views/ExternalBrowserView.swift`

**Step 1: Write the view**

```swift
import SwiftUI
import WebKit

/// Fullscreen browser view for the Apple TV external display.
/// No URL bar or floating menu — controlled entirely from the CLI.
struct ExternalBrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState

    var body: some View {
        WebViewContainer(
            browserState: browserState,
            handlerContext: serverState.handlerContext
        ) { wv in
            serverState.webView = wv
            serverState.handlerContext.webView = wv
        }
        .ignoresSafeArea()
    }
}
```

**Step 2: Add to Xcode project**

Add `ExternalBrowserView.swift` to the Views group in `Kelpie.xcodeproj/project.pbxproj`:
- PBXFileReference: `B100000042` → `ExternalBrowserView.swift`
- PBXGroup (Views `D100000003`): add to children
- PBXBuildFile: `A100000042` → Sources
- PBXSourcesBuildPhase (`E100000002`): add to files

**Step 3: Commit**

```bash
git add apps/ios/Kelpie/Views/ExternalBrowserView.swift apps/ios/Kelpie.xcodeproj/project.pbxproj
git commit -m "feat(ios): add ExternalBrowserView for Apple TV display"
```

---

### Task 2: ExternalDisplayManager

Singleton that monitors screen connections and manages the external window + server lifecycle.

**Files:**
- Create: `apps/ios/Kelpie/Browser/ExternalDisplayManager.swift`
- Modify: `apps/ios/Kelpie/Device/DeviceInfo.swift` — add `externalDisplay(port:screenSize:)` factory

**Step 1: Add `externalDisplay` factory to DeviceInfo**

In `DeviceInfo.swift`, add a static factory that creates a DeviceInfo for the external display. It uses the main device's identity with a `"-tv"` suffix and the external screen's resolution:

```swift
static func externalDisplay(port: Int, screenSize: CGSize, scale: CGFloat) -> DeviceInfo {
    let device = UIDevice.current
    return DeviceInfo(
        id: DeviceIdentity.id + "-tv",
        name: device.name + " (TV)",
        model: modelIdentifier(),
        width: Int(screenSize.width * scale),
        height: Int(screenSize.height * scale),
        port: port,
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    )
}
```

**Step 2: Write ExternalDisplayManager**

```swift
import UIKit
import SwiftUI

/// Manages an external display (Apple TV via AirPlay).
/// When a screen connects, spins up a WKWebView window with its own HTTP server and mDNS.
@MainActor
final class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published var isConnected = false

    private var externalWindow: UIWindow?
    private var serverState: ServerState?
    private var browserState: BrowserState?

    /// Port offset from the default — external display listens on 8421.
    private let externalPort: UInt16 = 8421

    private init() {}

    func startMonitoring() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidConnect(_:)),
            name: UIScreen.didConnectNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidDisconnect(_:)),
            name: UIScreen.didDisconnectNotification, object: nil
        )

        // If an external screen is already connected at launch, attach immediately.
        if UIScreen.screens.count > 1, let screen = UIScreen.screens.last {
            attach(to: screen)
        }
    }

    @objc private func screenDidConnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen else { return }
        attach(to: screen)
    }

    @objc private func screenDidDisconnect(_ notification: Notification) {
        detach()
    }

    private func attach(to screen: UIScreen) {
        guard externalWindow == nil else { return }

        let bs = BrowserState()
        let ss = ServerState(port: externalPort)
        browserState = bs
        serverState = ss

        let view = ExternalBrowserView(browserState: bs, serverState: ss)
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = .black

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = hostingController
        window.isHidden = false
        externalWindow = window

        ss.startHTTPServer()
        ss.startMDNS()
        isConnected = true

        print("[ExternalDisplay] Attached to \(screen.bounds.size), port \(externalPort)")
    }

    private func detach() {
        serverState?.stop()
        externalWindow?.isHidden = true
        externalWindow = nil
        serverState = nil
        browserState = nil
        isConnected = false

        print("[ExternalDisplay] Detached")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
```

**Step 3: Add both files to Xcode project**

Add `ExternalDisplayManager.swift` to the Browser group in `project.pbxproj`:
- PBXFileReference: `B100000043` → `ExternalDisplayManager.swift`
- PBXGroup (Browser `D100000004`): add to children
- PBXBuildFile: `A100000043` → Sources
- PBXSourcesBuildPhase: add to files

**Step 4: Commit**

```bash
git add apps/ios/Kelpie/Browser/ExternalDisplayManager.swift \
        apps/ios/Kelpie/Device/DeviceInfo.swift \
        apps/ios/Kelpie.xcodeproj/project.pbxproj
git commit -m "feat(ios): add ExternalDisplayManager for Apple TV AirPlay"
```

---

### Task 3: Wire into KelpieApp

Start external display monitoring when the app launches.

**Files:**
- Modify: `apps/ios/Kelpie/KelpieApp.swift`

**Step 1: Add monitoring to startServices()**

In `KelpieApp.swift`, add `ExternalDisplayManager.shared.startMonitoring()` to `startServices()`:

```swift
private func startServices() {
    serverState.startHTTPServer()
    serverState.startMDNS()
    ExternalDisplayManager.shared.startMonitoring()
    #if DEBUG
    AppRevealSetup.configure()
    #endif
}
```

No additional state objects needed — `ExternalDisplayManager` is a self-contained singleton.

**Step 2: Commit**

```bash
git add apps/ios/Kelpie/KelpieApp.swift
git commit -m "feat(ios): start external display monitoring on app launch"
```

---

### Task 4: Update docs

**Files:**
- Modify: `docs/functionality.md` — add Apple TV external display feature
- Modify: `docs/architecture.md` — mention external display subsystem if relevant

**Step 1: Add feature description**

Add an "External Display (Apple TV)" section to `docs/functionality.md` describing:
- Automatic detection via AirPlay
- Separate controllable device on port 8421
- Device name suffix "(TV)" in mDNS discovery
- Fullscreen WKWebView, no local UI chrome
- Teardown on disconnect

**Step 2: Commit**

```bash
git add docs/functionality.md docs/architecture.md
git commit -m "docs: add Apple TV external display feature"
```
