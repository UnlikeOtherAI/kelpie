# Kelpie — Project Guide

@./AGENTS.md

Android release signing requires all four configured secrets and verified APK/AAB signatures, with no unsigned fallback; follow [Android release signing](docs/api/native-browser-gateway-android.md#release-signing).

Windows/Linux outbound Nessie account connections follow [docs/desktop-nessie-connect.md](docs/desktop-nessie-connect.md).

## What This Is

Kelpie is an LLM-first browser for iOS and Android that enables language models to control real mobile browsers on the local network via mDNS discovery, HTTP API, and MCP. A companion Node.js CLI orchestrates individual and group commands across multiple devices.

Shared browser control and its separate headless conformance follow [docs/api/browser-control.md](docs/api/browser-control.md).

Android JNI/HTTP/MCP and inference follow [docs/api/native-browser-gateway-android.md](docs/api/native-browser-gateway-android.md); builds need Node 20+ and pnpm alongside Java/SDK.

npm package metadata and provenance follow AGENTS.md → Versioning.

## Claude-Specific Notes

- Keep instructions modular and prefer progressive disclosure.
- If deeper scoped behavior is needed, use `.claude/rules/` files.
- Prefer single-responsibility functions. When touching a method that mixes multiple concerns, split it along readability and responsibility boundaries before adding more logic.

## macOS SwiftUI + WebView Hit Testing

Three mechanisms silently kill button clicks — see the CRITICAL rule in AGENTS.md. Short version: **any button in a window containing a WebView must be an AppKit-backed NSButton subclass**. SwiftUI `Button` + WebView first-responder = broken every time.

## Debugging Protocol

Persistent pairing and exact-socket token reuse follow [Pairing & Authentication](docs/functionality.md#pairing--authentication).
Native outbound Nessie connectivity follows [the connection contract](docs/nessie-connect.md).

- **Always check logs first** before diving into source code. Check device HTTP server logs, mDNS advertisement logs, and CLI output before analyzing code.
- **Never manually fix state** — if the mDNS discovery, HTTP server, or MCP server is stuck, fix the code so it self-heals.
- **Kill stale Kelpie app instances before verification** when they could block ports, AppReveal, or input testing. Debug against one known app process, not a mixture of old and new sessions.

## Release Policy

- Every pushed fix requires a full release/publish cycle, even if it is only a small patch.
- The release cycle is not complete until the affected version is bumped, the affected artifact is published, the GitHub release is created, and the published artifact is installed locally and verified from that installed release.
- **Install the latest app on this Mac after every release.** When the macOS app is part of a release, build it, replace `/Applications/Kelpie.app` with the freshly built bundle (kill any running instance first, then `ditto` the build product into `/Applications`), and relaunch from `/Applications` so the running app always matches the release. A GitHub release alone does not update the installed app.

## Using Codex as an External Agent

When dispatching work to Codex (`timeout 1800 codex exec "<prompt>"`), minimize Claude token spend:

- **Launch with `run_in_background: true`** — you'll be notified on completion, no polling needed.
- **Do not read the full output** — Codex output can be 50K+ lines. Only read the tail (last 20-30 lines) to check final status.
- **Check if the process is still alive** with `wc -l` on the output file, not by reading content.
- **After completion**: check what files were created (`find native -type f | sort`), then build and test. Don't review Codex's intermediate reasoning.
- **If Codex times out** (exit 144): check created files — it usually finishes writing before the review pass that times out.
- **Token discipline**: Codex does the implementation, Claude does orchestration + verification. Don't duplicate work by reading files Codex already analyzed.

## Windows release ownership

The Windows desktop version is `project(kelpie_windows VERSION …)` in `apps/windows/CMakeLists.txt`, mirrored in `resources/kelpie.rc`, `device_info_windows.h` and `windows_runtime.cpp`. Releases use the CEF sandbox bootstrap and matching runtime assets. Verify
loopback readiness-token control and the CLI stdio alias bridge before publication.

Native browser gateway bindings and reproducible generated contract builds follow [docs/api/native-browser-gateway.md](docs/api/native-browser-gateway.md).
