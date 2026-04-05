# Kelpie — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the complete Kelpie system — CLI, iOS app, Android app — from the existing documentation spec.

**Architecture:** Three components communicate over HTTP/JSON on the local network. The CLI discovers native browser apps via mDNS and sends commands. Each native app embeds an HTTP server, MCP server, and mDNS advertiser. AppReveal is integrated in debug builds for automated testing.

**Tech Stack:** CLI: TypeScript/Node.js, Commander.js, bonjour-service, MCP SDK, tsup. iOS: Swift/SwiftUI, WKWebView, Swifter/Telegraph, Network.framework. Android: Kotlin/Compose, WebView+CDP, Ktor, NsdManager.

---

## Task Index

Tasks are ordered by dependency. Each task is a single PR.

| # | Task | Component | Depends On |
|---|------|-----------|------------|
| 01 | [Monorepo + Shared Types](./task-01-monorepo-shared-types.md) | Infra | — |
| 02 | [CLI Foundation](./task-02-cli-foundation.md) | CLI | 01 |
| 03 | [CLI Core Commands](./task-03-cli-core-commands.md) | CLI | 02 |
| 04 | [CLI Interaction + Scroll + Wait](./task-04-cli-interaction-scroll-wait.md) | CLI | 02 |
| 05 | [CLI DevTools + Browser Management](./task-05-cli-devtools-browser.md) | CLI | 02 |
| 06 | [CLI LLM-Optimized + Smart Queries](./task-06-cli-llm-smart-queries.md) | CLI | 02 |
| 07 | [CLI Group Commands](./task-07-cli-group-commands.md) | CLI | 03, 04, 05, 06 |
| 08 | [CLI MCP Server](./task-08-cli-mcp-server.md) | CLI | 07 |
| 09 | [CLI Help System + Build + Publish](./task-09-cli-help-build-publish.md) | CLI | 08 |
| 10 | [iOS App Foundation](./task-10-ios-foundation.md) | iOS | 01 |
| 11 | [iOS App Command Handlers](./task-11-ios-commands.md) | iOS | 10 |
| 12 | [Android App Foundation](./task-12-android-foundation.md) | Android | 01 |
| 13 | [Android App Command Handlers](./task-13-android-commands.md) | Android | 12 |
| 14 | [E2E Integration Tests](./task-14-e2e-tests.md) | All | 09, 11, 13 |

## Parallelism

Tasks 03-06 (CLI command groups) can run in parallel after Task 02.
Tasks 10-11 (iOS) can run in parallel with Tasks 03-09 (CLI).
Tasks 12-13 (Android) can run in parallel with Tasks 03-09 (CLI) and 10-11 (iOS).

## Testing Strategy

- **CLI:** Unit tests with mocked HTTP responses (vitest). Integration tests against a mock server.
- **iOS:** AppReveal in debug builds — LLM agents can discover, screenshot, and inspect the app via MCP. `#if DEBUG` guard only.
- **Android:** AppReveal as `debugImplementation` — same capabilities. `BuildConfig.DEBUG` guard.
- **E2E:** CLI → Simulator/Emulator pipeline. AppReveal validates app state after CLI commands.
