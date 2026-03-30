# Mollotov Browser — Mobile UI Specification

## Screen Inventory

| Screen | Description | Platform |
|---|---|---|
| **Browser** | Main screen — URL bar, WebView, status bar | iOS + Android |
| **Settings Panel** | Slide-in panel from right — device info, connection details | iOS + Android |

---

## Browser Screen (Main)

The primary and only screen. Full-screen WebView with a thin toolbar.

### Layout

```
┌──────────────────────────────────────────┐
│ Status Bar (OS)                          │
├──────────────────────────────────────────┤
│ ┌────────────────────────────┐  ┌──┐    │
│ │ https://example.com        │  │⚙ │    │
│ └────────────────────────────┘  └──┘    │
├──────────────────────────────────────────┤
│                                          │
│                                          │
│                                          │
│              WebView                     │
│           (full content)                 │
│                                          │
│                                          │
│                                          │
│                                          │
├──────────────────────────────────────────┤
│ ● Connected  192.168.1.42:8420     MCP ● │
└──────────────────────────────────────────┘
```

### Toolbar (Top)

- **URL Bar** — left-aligned, takes most of the width
  - Editable text field
  - Shows current URL
  - Tap to focus and type a new URL
  - Submit navigates to the URL
- **Settings Icon** — right side, gear icon
  - Tap opens the settings panel

### Status Bar (Bottom)

A thin bar showing connection state:

- **Connection indicator** — green dot when HTTP server is running, red when stopped
- **IP:Port** — current device IP and port (e.g., `192.168.1.42:8420`)
- **MCP indicator** — green dot when MCP server is active

### WebView (Center)

- Takes all remaining space between toolbar and status bar
- Standard web content rendering
- No custom overlays, no injected UI elements
- Handles all gestures normally (scroll, pinch zoom, tap)

---

## Settings Panel

Slides in from the right edge when the settings icon is tapped. Covers approximately 80% of the screen width on phones, 40% on tablets.

### Layout

```
┌──────────────────────────────────────────┐
│                          ┌──────────────┐│
│                          │  Settings    ││
│                          │              ││
│   (dimmed                │  Device      ││
│    WebView)              │  ──────────  ││
│                          │  Name: My iP ││
│                          │  Model: iPho ││
│                          │  Platform: i ││
│                          │  OS: 17.4    ││
│                          │  App: 1.0.0  ││
│                          │              ││
│                          │  Connection  ││
│                          │  ──────────  ││
│                          │  IP: 192.168 ││
│                          │  Port: 8420  ││
│                          │  mDNS: ● Act ││
│                          │  MCP: ● Acti ││
│                          │              ││
│                          │  Connect     ││
│                          │  ──────────  ││
│                          │  HTTP:       ││
│                          │  http://192. ││
│                          │  MCP:        ││
│                          │  http://192. ││
│                          │              ││
│                          │  [QR Code]   ││
│                          │              ││
│                          │  Settings    ││
│                          │  ──────────  ││
│                          │  Port: [8420]││
│                          │  Name: [My i]││
│                          └──────────────┘│
└──────────────────────────────────────────┘
```

### Sections

**Device Info**
- Device name (user-configurable)
- Model (e.g., "iPhone 15 Pro", "Pixel 8")
- Platform (iOS / Android)
- OS version
- App version
- Viewport resolution
- Device pixel ratio

**Connection Status**
- IP address
- Port number
- mDNS status (active/inactive) with service name
- MCP server status (active/inactive)
- HTTP server status (active/inactive)

**How to Connect**
- HTTP base URL (copyable): `http://192.168.1.42:8420/v1/`
- MCP endpoint (copyable): `http://192.168.1.42:8420/mcp`
- QR code encoding the HTTP base URL (for quick scanning)
- CLI discovery command: `mollotov discover`

**Settings**
- Port number (editable, requires restart)
- Device name (editable)

### Interactions

- **Open**: Tap settings gear icon — panel slides in from right
- **Close**: Tap dimmed area outside panel, or swipe right on panel
- **Copy URLs**: Tap any URL to copy to clipboard
- **QR Code**: Always visible, updates if port changes

---

## Tablet Adaptations

On iPads and Android tablets:

- Status bar text can be larger
- Settings panel is narrower (40% width) since there's more space
- WebView remains the dominant element
- No split-view or multi-window support (keep it simple)

---

## Platform-Specific Notes

### iOS (SwiftUI)
- Use `NavigationStack` for settings presentation, or a custom sheet
- `WKWebView` wrapped in `UIViewRepresentable`
- Status bar uses SF Symbols for indicators
- Settings panel via `.sheet` or custom slide-over

### Android (Jetpack Compose)
- Use `ModalNavigationDrawer` (end-aligned) for settings panel
- `AndroidView` wrapping `WebView`
- Material 3 icons for indicators
- Bottom bar as a custom `BottomAppBar` or simple `Row`

---

## Theme

- **Light mode only** for v1 (dark mode later)
- System font throughout
- Minimal color: mostly neutral with green/red status indicators
- No branding in the browser chrome — the app icon and name handle branding
