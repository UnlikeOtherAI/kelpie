# Mollotov — Tech Stack

## Platform Matrix

| Component | Technology | Language | Notes |
|---|---|---|---|
| **iOS App** | SwiftUI + WKWebView | Swift | Native WebKit browser, Bonjour for mDNS |
| **Android App** | Jetpack Compose + WebView | Kotlin | Chrome DevTools Protocol for DOM access |
| **CLI** | Node.js | TypeScript | Published as `@unlike-other-ai/mollotov` |
| **MCP Servers** | MCP SDK | Per-platform | Browser-embedded + CLI standalone |

---

## iOS App

| Concern | Choice | Why |
|---|---|---|
| **UI Framework** | SwiftUI | Modern declarative UI, native performance |
| **Browser Engine** | WKWebView | Only allowed engine on iOS; native screenshot + DOM APIs |
| **DOM Access** | WebKit Message Handlers + `evaluateJavaScript` via native bridge | Calls go through WKWebView's native API; some features require ephemeral bridge scripts |
| **Screenshots** | `WKWebView.takeSnapshot(with:)` | Native API, no JS required |
| **HTTP Server** | [Swifter](https://github.com/httpswift/swifter) or [Telegraph](https://github.com/nicklama/Telegraph) | Lightweight embedded HTTP server for receiving commands |
| **mDNS** | `NWListener` + `NWBrowser` (Network framework) | Built into iOS — zero dependencies. Replaces deprecated `NetService` (iOS 16+) |
| **MCP Server** | Custom implementation over HTTP transport | MCP protocol over the same HTTP server |
| **Networking** | URLSession | Standard iOS networking |
| **Min Target** | iOS 16+ | WKWebView snapshot API stability |

### iOS — Required Info.plist Entries

```xml
<!-- Local network access prompt (required iOS 14+) -->
<key>NSLocalNetworkUsageDescription</key>
<string>Mollotov uses the local network to receive browser automation commands from the CLI.</string>

<!-- Bonjour service types for mDNS (required for NWListener/NWBrowser) -->
<key>NSBonjourServices</key>
<array>
  <string>_mollotov._tcp</string>
</array>
```

Without these entries, iOS will silently block local network access and mDNS advertisement.

### iOS — Key APIs

- `WKWebView.evaluateJavaScript(_:)` — DOM queries and reads via native bridge
- `WKWebView.takeSnapshot(with:completionHandler:)` — viewport screenshots
- `WKNavigationDelegate` — navigation lifecycle
- `WKUIDelegate` — dialogs, new windows
- `WKWebView.scrollView` — native scroll control
- `UIView.drawHierarchy(in:afterScreenUpdates:)` — full-page screenshots
- `NWListener` / `NWBrowser` (Network framework) — mDNS advertisement and discovery

---

## Android App

| Concern | Choice | Why |
|---|---|---|
| **UI Framework** | Jetpack Compose | Modern declarative UI, Material 3 |
| **Browser Engine** | Android WebView (Chromium-based) | Full CDP support for DOM access |
| **DOM Access** | Chrome DevTools Protocol (CDP) via `WebView.setWebContentsDebuggingEnabled` | Full DOM tree via protocol — no scripts enter the page context |
| **Screenshots** | `PixelCopy.request()` or `View.drawToBitmap()` | Hardware-accelerated capture |
| **HTTP Server** | [Ktor](https://ktor.io/) (embedded server) or [NanoHTTPD](https://github.com/NanoHttpd/nanohttpd) | Ktor preferred — Kotlin-native, coroutine-based |
| **mDNS** | `NsdManager` (Network Service Discovery) | Built into Android — zero dependencies |
| **MCP Server** | Custom implementation over HTTP transport | MCP protocol over the same Ktor server |
| **Min Target** | Android API 28+ (Android 9) | CDP support in WebView |

### Android — Key APIs

- `WebView.evaluateJavascript()` — DOM queries via native bridge
- `WebView.setWebContentsDebuggingEnabled(true)` — enables CDP
- CDP `DOM.getDocument` / `DOM.querySelectorAll` — full DOM via protocol
- CDP `Page.captureScreenshot` — screenshots via protocol
- `PixelCopy.request()` — hardware screenshot fallback
- `NsdManager.registerService()` — mDNS advertisement
- `NsdManager.discoverServices()` — mDNS discovery

### Android — CDP vs evaluateJavascript

Both paths are available. CDP is preferred for DOM operations because:
- No script enters the page's JS context
- Access to computed styles, layout metrics, accessibility tree
- Network interception, console logs, performance metrics
- Same protocol Playwright uses internally

`evaluateJavascript` is the fallback for simpler queries where CDP is overkill.

---

## CLI

| Concern | Choice | Why |
|---|---|---|
| **Runtime** | Node.js 20+ | LTS, native fetch, stable ESM |
| **Language** | TypeScript 5+ | Type safety, LLM-readable code |
| **CLI Framework** | [Commander.js](https://github.com/tj/commander.js/) | Mature, lightweight, great help generation |
| **mDNS Discovery** | [bonjour-service](https://www.npmjs.com/package/bonjour-service) | Pure JS Bonjour/mDNS — works on macOS, Linux, Windows |
| **HTTP Client** | Native `fetch` | No dependencies, built into Node 20+ |
| **MCP Server** | `@modelcontextprotocol/sdk` | Official MCP SDK for TypeScript |
| **Output Formatting** | [chalk](https://www.npmjs.com/package/chalk) + [cli-table3](https://www.npmjs.com/package/cli-table3) | Terminal colors + table formatting |
| **Build** | [tsup](https://github.com/egoist/tsup) | Fast bundler for CLI distribution |
| **Package Manager** | pnpm | Workspace-aware, fast, disk-efficient |
| **Publishing** | npm as `@unlike-other-ai/mollotov` | Scoped under org |

### CLI — Project Structure

```
packages/
  cli/                    # @unlike-other-ai/mollotov
    src/
      commands/           # Commander command definitions
      discovery/          # mDNS browser discovery
      client/             # HTTP client for browser communication
      group/              # Group command orchestration
      mcp/                # MCP server implementation
      help/               # LLM help system
    bin/
      mollotov.ts         # Entry point
    package.json
```

---

## Shared / Cross-Cutting

| Concern | Choice | Notes |
|---|---|---|
| **Protocol** | HTTP/JSON | All browser-CLI communication over REST |
| **MCP Transport** | Streamable HTTP (SSE) | Standard MCP transport for both browser and CLI servers |
| **mDNS Service Type** | `_mollotov._tcp` | Service discovery identifier |
| **mDNS TXT Records** | `id`, `name`, `model`, `platform`, `width`, `height`, `port`, `version` | Device metadata for discovery |
| **API Versioning** | URL prefix `/v1/` | Forward-compatible |
| **Image Format** | PNG (screenshots) | Lossless, LLM-friendly |
| **Monorepo** | pnpm workspaces | CLI, shared types, and native app projects all in one repo |

---

## Repository Structure

```
mollotov/
  packages/
    cli/                  # Node.js CLI — @unlike-other-ai/mollotov
    shared/               # Shared TypeScript types and constants
  apps/
    ios/                  # Xcode project — Mollotov Browser
    android/              # Android Studio project — Mollotov Browser
  docs/                   # This documentation
```

---

## Dependencies Summary

### iOS (Swift Package Manager)

| Package | Purpose |
|---|---|
| Swifter or Telegraph | Embedded HTTP server |

Everything else is built into iOS SDK (WKWebView, NetService, URLSession).

### Android (Gradle)

| Package | Purpose |
|---|---|
| Ktor Server (Netty) | Embedded HTTP server |
| Kotlinx Serialization | JSON handling |
| Material 3 | UI components |

WebView, NsdManager, PixelCopy are all Android SDK built-ins.

### CLI (npm)

| Package | Purpose |
|---|---|
| commander | CLI framework |
| bonjour-service | mDNS discovery |
| @modelcontextprotocol/sdk | MCP server |
| chalk | Terminal colors |
| cli-table3 | Table formatting |
| tsup | Build/bundle |
| typescript | Language |

---

## Build & Run

| Component | Build Command | Run Command |
|---|---|---|
| CLI | `pnpm build` | `mollotov` (global) or `pnpm dev` |
| iOS | Xcode build | Run on device/simulator |
| Android | `./gradlew assembleDebug` | Run on device/emulator |
