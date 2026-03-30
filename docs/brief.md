# Mollotov — Product Brief

## What It Is

Mollotov is an **LLM-first browser** for iOS and Android (phones and tablets) paired with a **Node.js CLI** that enables large language models to discover, control, and orchestrate multiple browser instances on a local network.

Think Playwright-style automation, but running natively on real mobile devices — no emulators, no persistent content scripts, no desktop required. Android has near-full parity with desktop automation via CDP; iOS covers core workflows with some platform-specific gaps (see [Platform Support Matrix](api/README.md)).

## The Problem

LLMs that need to interact with web content on mobile devices today have no good options:

- **Playwright/Puppeteer** only run headless desktop browsers — no real mobile testing
- **Appium/device farms** are complex, expensive, and not designed for LLM workflows
- **Browser extensions** require JS injection that breaks CSP, alters DOM, and gets detected
- **No group control** — orchestrating actions across multiple devices simultaneously doesn't exist in any LLM-friendly tool

## The Solution

Two components that work together:

### 1. Mollotov Browser (Native iOS + Android App)

A minimal native browser built on each platform's WebView engine (WKWebView / Android WebView) that:

- Exposes **rich browser automation capabilities** through native WebView APIs and CDP (Android). Coverage varies by platform — Android has near-full parity with desktop automation; iOS has some gaps where WKWebView lacks native APIs (see [Platform Support Matrix](api/README.md))
- Advertises itself via **mDNS** on the local network (`_mollotov._tcp`)
- Runs a local **HTTP + MCP server** accepting commands from the CLI or any MCP-compatible client
- Takes screenshots, reads DOM, navigates, clicks, fills forms, scrolls — all via native bridge
- Provides a minimal UI: URL bar + settings panel with connection info

### 2. Mollotov CLI (`@unlike-other-ai/mollotov`)

A Node.js CLI published on npm that:

- **Discovers** all Mollotov browser instances on the local network via mDNS
- Sends **individual commands** to any single device
- Sends **group commands** to all (or a subset of) devices simultaneously
- Provides **resolution-aware methods** (e.g., `scroll2`) that adapt behavior per device viewport
- Implements **smart group queries** (e.g., `findButton` returns only the devices where the element was found, letting the LLM decide next steps)
- Includes **built-in LLM help** — every command has structured descriptions explaining what it does, when to use it, and expected inputs/outputs
- Exposes everything through its own **MCP server** for direct LLM integration

## Key Features

| Feature | Description |
|---|---|
| **No persistent content scripts** | Page interaction through native WebView APIs and CDP (Android). Some iOS features use lightweight bridge scripts for capabilities WKWebView doesn't expose natively (console capture, mutation observation). No browser extension model, no content script persistence across navigations. |
| **mDNS discovery** | Browsers advertise `_mollotov._tcp` with device metadata (name, platform, resolution, version) — CLI auto-discovers them |
| **Individual control** | Target any single device by name/IP for precise commands |
| **Group commands** | Send the same command to all devices — fill forms, navigate, click simultaneously |
| **Smart queries** | `findButton("Submit")` across all devices returns which ones found it — LLM makes the decision |
| **Resolution-aware** | Methods like `scroll2` adapt scroll distance, tap coordinates, and element visibility per device viewport |
| **Full DOM access** | Read and query the complete DOM tree via native WebView APIs (both platforms) and CDP (Android) |
| **Screenshots** | Capture full-page or viewport screenshots on any device on demand |
| **MCP everywhere** | Both the browser and CLI expose MCP APIs — any MCP-compatible LLM can drive them directly |
| **Native apps** | Real native iOS and Android apps — not web wrappers, not Electron |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Local Network                         │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Mollotov    │  │  Mollotov    │  │  Mollotov    │  │
│  │  Browser     │  │  Browser     │  │  Browser     │  │
│  │  (iPhone)    │  │  (iPad)      │  │  (Android)   │  │
│  │              │  │              │  │              │  │
│  │  HTTP + MCP  │  │  HTTP + MCP  │  │  HTTP + MCP  │  │
│  │  mDNS ●      │  │  mDNS ●      │  │  mDNS ●      │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                 │           │
│         └────────────┬────┴────┬────────────┘           │
│                      │         │                        │
│              ┌───────┴─────────┴────────┐               │
│              │     Mollotov CLI         │               │
│              │   (Node.js / MCP)        │               │
│              │                          │               │
│              │  mDNS Discovery          │               │
│              │  Individual Commands     │               │
│              │  Group Commands          │               │
│              │  LLM Help System         │               │
│              └──────────┬───────────────┘               │
│                         │                               │
│                    ┌────┴────┐                           │
│                    │   LLM   │                           │
│                    └─────────┘                           │
└─────────────────────────────────────────────────────────┘
```

For detailed system design, see [architecture.md](architecture.md).
For API method reference, see [api/](api/).
For CLI command reference, see [cli.md](cli.md).

## MVP Scope

### Phase 1 — Single Device
- Android browser app with HTTP server + MCP
- Core navigation, screenshot, DOM access, click, fill, scroll
- CLI with single-device control
- mDNS advertisement and discovery

### Phase 2 — Multi-Device
- Group commands in CLI
- Smart queries (`findButton`, `findElement`)
- Resolution-aware methods (`scroll2`)
- iOS browser app

### Phase 3 — Polish
- CLI MCP server for direct LLM integration
- Built-in LLM help system
- npm publish `@unlike-other-ai/mollotov`
- Settings panel with connection info and QR code

## Simulator & Emulator Support

Mollotov works on **real devices, simulators, and emulators**. A developer with no physical phones can run 5-6 iOS Simulators or Android Emulators with different screen sizes, and each instance advertises itself via mDNS and accepts commands like a real device.

- **iOS Simulator** — each Simulator instance runs its own Mollotov app, advertises on the host's network via Bonjour, and is discoverable by the CLI
- **Android Emulator** — each emulator instance runs its own Mollotov app; port forwarding (`adb forward`) maps each emulator's HTTP server to a host port for CLI discovery
- **Mixed fleets** — real devices and simulators can coexist on the same network; the CLI treats them identically
- **Zero-setup goal** — clone the repo, open in Xcode/Android Studio, run on simulator, `mollotov discover` finds it

The `getDeviceInfo` endpoint (see [api/core.md](api/core.md)) includes an `isSimulator` field so the LLM knows whether it's talking to a real device or a simulated one.

## Target Users

- **LLM agents** that need to interact with real mobile browsers
- **Developers** building LLM-powered testing and automation — including those with no physical devices (simulator-only workflows)
- **QA teams** running LLM-driven cross-device testing
- **Researchers** studying LLM web interaction on real devices

## Publishing

- **npm**: `@unlike-other-ai/mollotov`
- **App Store**: Mollotov Browser
- **Play Store**: Mollotov Browser
- **Icon/branding**: Mollotov (two Ls)

## App Icon

The canonical app icon is a kawaii fire character in pastel yellow-to-orange tones.

- **Source file (1024x1024)**: [icon-1024.png](icon-1024.png) — use this for App Store and Play Store submission
- **Assets directory**: `assets/icon-1024.png`
- **Style**: Flat pastel, kawaii Japanese-style fire, happy/chuckling expression, no outlines, no text
