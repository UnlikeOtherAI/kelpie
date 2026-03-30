# Task 10: iOS App Foundation — Project + UI + WebView + Network

**Component:** iOS
**Depends on:** Task 01
**Estimated size:** ~800 lines

## Goal

Create the complete iOS app foundation: Xcode project, SwiftUI browser UI, WKWebView integration, embedded HTTP server, mDNS advertisement, and AppReveal debug integration.

## Files to Create

```
apps/ios/
  Mollotov.xcodeproj/
  Mollotov/
    MollotovApp.swift                    # App entry point
    Info.plist                           # Network permissions, Bonjour config
    Assets.xcassets/                     # App icon from assets/icon-1024.png

    Views/
      BrowserView.swift                  # Main browser screen (URL bar + WebView)
      SettingsView.swift                 # Settings panel (IP, port, mDNS status, QR)
      URLBarView.swift                   # URL bar component

    Browser/
      WebViewCoordinator.swift           # WKWebView wrapper with delegate handling
      BrowserState.swift                 # Observable state: URL, title, loading, canGoBack/Forward

    Network/
      HTTPServer.swift                   # Embedded HTTP server (Swifter or Telegraph)
      Router.swift                       # Route registration and dispatching
      MDNSAdvertiser.swift               # Network.framework mDNS advertisement

    Device/
      DeviceIdentity.swift               # Stable UUID (identifierForVendor + Keychain)
      DeviceInfo.swift                   # Collect all device metadata

    Debug/
      AppRevealSetup.swift               # #if DEBUG AppReveal integration
```

## Steps

### 1. Xcode Project

Create iOS project targeting iOS 16+. Swift Package Manager dependencies:
- Swifter (or Telegraph) for HTTP server
- AppReveal (debug only): `https://github.com/UnlikeOtherAI/AppReveal.git` from `0.2.0`

### 2. Info.plist

Required entries (from docs/tech-stack.md):
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Mollotov uses the local network to receive browser automation commands from the CLI.</string>

<key>NSBonjourServices</key>
<array>
  <string>_mollotov._tcp</string>
  <string>_appreveal._tcp</string>
</array>
```

### 3. App Entry Point (`MollotovApp.swift`)

```swift
@main
struct MollotovApp: App {
    @StateObject private var browserState = BrowserState()
    @StateObject private var serverState = ServerState()

    var body: some Scene {
        WindowGroup {
            BrowserView(browserState: browserState, serverState: serverState)
                .onAppear { startServices() }
        }
    }

    private func startServices() {
        serverState.startHTTPServer()
        serverState.startMDNS()
        #if DEBUG
        AppReveal.start()
        #endif
    }
}
```

### 4. Browser UI

**BrowserView** — Full-screen layout: URL bar at top, WKWebView filling remaining space, settings button.

**URLBarView** — Text field for URL input, go button, loading indicator. Reads from `browserState.currentURL`, writes on submit.

**SettingsView** — Sheet that slides in showing: device name, IP address, port, mDNS status (advertising/not), device ID, app version. QR code with connection URL.

### 5. WebView Integration

**WebViewCoordinator** — Wraps `WKWebView` in a `UIViewRepresentable`. Implements `WKNavigationDelegate` for navigation lifecycle and `WKUIDelegate` for dialogs/new windows.

**BrowserState** — `@Published` properties: `currentURL`, `pageTitle`, `isLoading`, `canGoBack`, `canGoForward`, `progress`.

### 6. HTTP Server

**HTTPServer** — Starts Swifter/Telegraph on port 8420 (configurable). Registers routes via `Router`. Handles JSON request/response cycle.

**Router** — Maps `POST /v1/{method}` routes to handler functions. Parses JSON body, calls handler, returns JSON response. Error handling returns standard error format.

Start with stub handlers that return `{"success": false, "error": {"code": "NOT_IMPLEMENTED"}}` — actual implementations come in Task 11.

### 7. mDNS Advertisement

**MDNSAdvertiser** — Uses `NWListener` (Network.framework) to advertise `_mollotov._tcp` with TXT records: id, name, model, platform, width, height, port, version.

### 8. Device Identity

**DeviceIdentity** — Returns stable UUID. Primary: `UIDevice.current.identifierForVendor`. Backup: Keychain-stored UUID. Simulator: generates and stores UUIDv4.

### 9. AppReveal Integration (Debug Only)

**AppRevealSetup** — Everything wrapped in `#if DEBUG`:
```swift
#if DEBUG
import AppReveal

enum AppRevealSetup {
    static func configure() {
        AppReveal.start()
    }
}
#endif
```

Register optional providers for state, navigation, and feature flags if applicable.

### 10. Commit

```bash
git add apps/ios/ && git commit -m "feat: iOS app foundation — UI, WebView, HTTP server, mDNS"
```

## Acceptance Criteria

- [ ] Xcode project builds without warnings (iOS 16+ target)
- [ ] App launches in Simulator showing URL bar and WebView
- [ ] Typing a URL and pressing Go navigates the WebView
- [ ] Back/forward buttons work when history exists
- [ ] Settings panel shows device IP, port, mDNS status
- [ ] HTTP server starts on port 8420 and responds to requests
- [ ] `curl http://localhost:8420/v1/get-device-info` returns JSON (even if stub)
- [ ] mDNS advertises `_mollotov._tcp` — discoverable via `dns-sd -B _mollotov._tcp local.`
- [ ] TXT records include: id, name, model, platform, width, height, port, version
- [ ] Device ID is stable across app restarts (Simulator)
- [ ] AppReveal is active in debug builds — discoverable via `dns-sd -B _appreveal._tcp local.`
- [ ] AppReveal is NOT present in release builds (verify with `#if DEBUG`)
- [ ] Info.plist has `NSLocalNetworkUsageDescription` and `NSBonjourServices`
- [ ] App icon uses the kawaii fire character from `assets/icon-1024.png`

---

- [ ] **Have you run an adversarial review with Codex?**
