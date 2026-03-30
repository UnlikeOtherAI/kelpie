<p align="center">
  <img src="assets/icon-1024.png" width="128" height="128" alt="Mollotov icon">
</p>

<h1 align="center">Mollotov</h1>

<p align="center">
  LLM-first browser for iOS, Android, and macOS.<br>
  Control real browsers via mDNS discovery, HTTP API, and MCP. AirPlay to Apple TV supported.
</p>

<p align="center">
  <a href="https://unlikeotherai.github.io/mollotov">Website</a> &middot;
  <a href="docs/brief.md">Product Brief</a> &middot;
  <a href="docs/architecture.md">Architecture</a> &middot;
  <a href="docs/api/">API Reference</a> &middot;
  <a href="docs/cli.md">CLI Reference</a>
</p>

---

## What it is

Native iOS, Android, and macOS browser apps paired with a Node.js CLI. Language models discover devices on the local network, then control them: navigate, screenshot, read DOM, click, fill forms, scroll, capture network traffic, evaluate JS. Works on real devices, simulators, and emulators. AirPlay an iPhone to an Apple TV and it appears as a second controllable device.

No emulators pretending to be phones. No persistent content scripts. No browser extensions. Real browsers on real hardware, fully controllable by LLMs.

## Install

```
npm install -g @unlikeotherai/mollotov
```

## Quick start

1. Build and run the iOS or Android app on a device or simulator
2. `mollotov discover` — lists all Mollotov instances on your network
3. `mollotov navigate --url https://example.com` — or connect your LLM via MCP

## Key features

- **Real browsers** — WKWebView (iOS/macOS), CEF (macOS), Android WebView, with native user agents
- **Apple TV support** — AirPlay from iPhone/iPad to Apple TV, TV appears as a separate controllable device
- **mDNS discovery** — devices advertise `_mollotov._tcp`, CLI auto-discovers them
- **HTTP + MCP API** — navigate, screenshot, DOM, click, fill, scroll, JS eval
- **Group commands** — send commands to all devices simultaneously
- **Annotated screenshots** — numbered labels on interactive elements for visual-first automation
- **Safari / Chrome auth** — one-tap login using saved passwords, cookies sync back
- **Network inspector** — capture XHR and fetch traffic with headers, bodies, timing
- **Console capture** — read console output and JS errors with stack traces

## Architecture

```
  +-----------+    +-----------+    +-----------+    +-----------+
  | Mollotov  |    | Mollotov  |    | Mollotov  |    | Apple TV  |
  | (iPhone)  |    | (iPad)    |    | (Android) |    | (AirPlay) |
  | HTTP+MCP  |    | HTTP+MCP  |    | HTTP+MCP  |    | HTTP+MCP  |
  | mDNS      |    | mDNS      |    | mDNS      |    | mDNS      |
  +-----+-----+    +-----+-----+    +-----+-----+    +-----+-----+
        |               |               |               |
        +-------+-------+-------+-------+-------+-------+
                |               |
         +------+---------------+------+
         |      Mollotov CLI           |
         |      (Node.js / MCP)        |
         +-------------+---------------+
                       |
                  +----+----+
                  |   LLM   |
                  +---------+
```

## Repository structure

```
apps/
  ios/          iOS app (Swift, SwiftUI, WKWebView) + Apple TV via AirPlay
  android/      Android app (Kotlin, Jetpack Compose, WebView)
  macos/        macOS app (Swift, SwiftUI, WKWebView + CEF)
packages/
  cli/          Node.js CLI and MCP server
docs/           Product brief, architecture, API reference, CLI docs
```

## Documentation

| Doc | Description |
|-----|-------------|
| [Product Brief](docs/brief.md) | What, why, how, MVP scope |
| [Architecture](docs/architecture.md) | Components, data flow, protocols |
| [Tech Stack](docs/tech-stack.md) | Platform choices, dependencies |
| [Feature Catalogue](docs/functionality.md) | Every user-facing feature |
| [API Reference](docs/api/) | All HTTP/MCP methods |
| [CLI Reference](docs/cli.md) | Commands, flags, group operations |

## Sister projects

### [AppReveal](https://github.com/UnlikeOtherAI/AppReveal)

Drop-in Swift package that turns any iOS app into an MCP-controllable agent. 44 tools: screenshot, tap, DOM, forms, navigation, view hierarchy. Discovered via mDNS, accessed over streamable HTTP. Used by Mollotov for debug integration.

## License

MIT
