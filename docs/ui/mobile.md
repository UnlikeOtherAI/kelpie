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

**Help**
- Show Welcome Screen
- Open Mollotov Website
- Open GitHub Repository
- Open UnlikeOtherAI

### Interactions

- **Open**: Tap settings gear icon — panel slides in from right
- **Close**: Tap dimmed area outside panel, or swipe right on panel
- **Copy URLs**: Tap any URL to copy to clipboard
- **QR Code**: Always visible, updates if port changes
- **Help / Welcome**: `Show Welcome Screen` reopens the welcome card even if automatic launch presentation was disabled earlier
- **iPad App Menu**: The same welcome and support links are also available directly under the app menu's `Settings` item
- **iPad View Menu**: `Full Width` and the currently fitting staged phone, tablet, and laptop viewport presets are available directly in the `View` menu

---

## Tablet Adaptations

On iPads and Android tablets:

- Status bar text can be larger
- Settings panel is narrower (40% width) since there's more space
- WebView remains the dominant element
- No split-view or multi-window support (keep it simple)
- Back and forward controls use full 44-point button targets instead of icon-only tap slivers.

On iPad specifically:

- The first-launch welcome card should cap its width to a modal-like width instead of expanding across the whole tablet.
- The settings help section can reopen the welcome card even when automatic launch presentation was previously disabled.
- The app menu also exposes `Show Welcome Screen`, `Open Mollotov Website`, `Open GitHub Repository`, and `Open UnlikeOtherAI` directly under `Settings`.
- The `View` menu lists `Full Width` plus every staged phone, tablet, and laptop viewport preset that currently fits the tablet geometry.
- The URL bar includes a `3D` shortcut beside the address field so the 3D DOM inspector is always one tap away on tablets.
- The floating menu includes a phone icon that opens a pill picker for staged device-class viewports.
- The floating menu also includes `AI` and `3D` actions, and the fan widens automatically as actions are added so the buttons stay separated on-screen.
- The picker uses the shared fitting preset list from the staged viewport catalog, sorted by screen size, and shows full labels such as `6.1" Compact`, `11" iPad Pro`, and `13" Laptop`.
- The picker opens in its own lane outside the floating action fan and spills into extra columns if needed, so the pills do not sit on top of the action buttons.
- When a preset is enabled, the browser renders inside a centered phone-sized stage instead of taking the full tablet width.
- The staged viewport follows tablet orientation: portrait tablet -> phone portrait frame, landscape tablet -> phone landscape frame.
- The staged viewport shows a persistent black close button with a white border above and to the left of the browser frame, so the smaller viewport can always be dismissed directly without sharing the browser edge.
- A centered pill sits above the staged viewport with clear spacing and shows the simulated inches band and pixel range for the active preset.
- The floating-menu fan widens automatically as actions are added, so the icon buttons keep comfortable spacing instead of colliding.
- While the 3D DOM inspector is active, iPad shows a native bottom control strip with rotate mode (`hand`), scroll mode (`vertical arrows`), zoom in, zoom out, reset, and exit buttons.
- In rotate mode, one-finger drag rotates the 3D scene; in scroll mode, one-finger vertical drag scrolls the underlying page without leaving 3D.
- Pinch still zooms the 3D camera on iPad in either mode.
- Android tablets mirror the same staged viewport picker, colors, close button, summary pill, and larger navigation targets.
- Android mirrors the same settings help actions and welcome-screen trigger behavior as iPad.
- Android mirrors the same AI entry points, 3D inspector floating-menu entry, and native 3D control strip behavior as iPad.

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
