# Per-Tab Partition + Name — macOS

Parent: [../2026-05-16-per-tab-partition-and-name.md](../2026-05-16-per-tab-partition-and-name.md)

## Engine scope

**WKWebView path only.** macOS Kelpie can run on either WKWebView or CEF (`RendererState.activeEngine`). For the CEF path, `new-tab` with `partition` returns `{"success": false, "error": "PARTITION_UNSUPPORTED_ON_CHROMIUM"}`. Engine-agnostic partition support is a follow-up requiring `native/engine-chromium-desktop` extensions and is explicitly out of scope.

## Pre-conditions

- Shared types from [./shared.md](./shared.md) merged.
- macOS deployment target stays as-is (already ≥ 14 per project state).

## Files

### `apps/macos/Kelpie/Browser/TabStore.swift`

Extend `Tab` struct / class with:
```swift
var name: String?
var partition: String?
var persistent: Bool
```

Extend `TabStore.addTab(...)` to accept `name`, `partition`, `persistent`.

### `apps/macos/Kelpie/Browser/PartitionRegistry.swift` (new)

Mirror of the iOS `PartitionRegistry` (same API, same validation, same UserDefaults persistence, same reconciliation policy, same `deleting`-flag race protection, same orphan handling). The two registries can later be lifted into a shared Swift package if duplication becomes a problem — defer that.

See [ios.md § PartitionRegistry](./ios.md) for the full definition. The macOS file is a copy with `import AppKit` instead of `import UIKit` and the same `@MainActor` isolation.

### `apps/macos/Kelpie/Browser/WKWebViewRenderer.swift`

Extend init to accept an optional `WKWebsiteDataStore`. When provided, use it on `WKWebViewConfiguration`; otherwise use the existing default.

Cookie-touching code that reads `webView.configuration.websiteDataStore.httpCookieStore` continues to work — it just now points at the partition store when one is set.

### `apps/macos/Kelpie/Handlers/HandlerContext.swift` — `SharedCookieJar` exclusion (CRITICAL)

Verified during planning: `SharedCookieJar` (file at `~/.kelpie/session/cookies.json`) is *not* passive — `HandlerContext` actively syncs cookies between every WKWebView tab through it (`persistRendererCookiesToSharedJar` writes, `syncSharedCookiesIntoRenderer` reads-and-pushes). Without intervention, partitioned tabs would leak cookies into the shared jar and have every other tab's cookies pushed back on next sync. This defeats partition isolation.

**Rule:** a tab whose `partition != nil` must never participate in `SharedCookieJar`. Concretely:

1. In `persistRendererCookiesToSharedJar` (line ~551): early-return if the active tab has a partition. The shared jar reflects only the default-store tab(s).
2. In `syncSharedCookiesIntoRenderer` (line ~528): early-return if the active tab has a partition. Partitioned tabs never receive cookies from the shared jar.
3. In `allCookies` / `setCookie` / `deleteCookie` / `deleteAllCookies` (lines ~462–525): when the active tab is partitioned, operate directly on `tab.webView.configuration.websiteDataStore.httpCookieStore` and skip every `SharedCookieJar.{load,save}` call.
4. In `CookieMigrator.swift` (renderer engine switch): if any open tab has `partition != nil`, **reject the engine switch** with `ENGINE_SWITCH_BLOCKED_BY_PARTITION` — partitioned WK stores cannot be losslessly migrated to a single CEF browser. Document this in `docs/api/browser.md`.

No changes to `SharedCookieJar.swift` itself — it remains the snapshot/restore helper for the default store. All filtering happens at the callsites.

### `apps/macos/Kelpie/Browser/SessionStore.swift`

Persist `name`, `partition`, `persistent` per tab. On restart, restore tabs with `persistent: true` partitions; discard tabs with `persistent: false`.

### `apps/macos/Kelpie/Handlers/BrowserManagementHandler.swift`

- `newTab`:
  - If `context.renderer?.engineName == "chromium"` and `body["partition"]` is set, return `PARTITION_UNSUPPORTED_ON_CHROMIUM`.
  - Otherwise read `name`, `partition`, `persistent`. Validate. Call `tabStore.addTab(...)`. Map registry errors.
- `getTabs`: include new fields.
- Add `getPartitions(_ body:)`.
- Add `deletePartition(_ body:)` — close partition tabs, then `partitionRegistry.delete`.

### `apps/macos/Kelpie/Server/Router.swift`

Register `get-partitions` and `delete-partition` routes.

### `apps/macos/Kelpie/Browser/TabBarView.swift`

Surface `tab.name` in the tab pill label when present (fall back to `tab.title`). Truncate the same way as the title.

### Tests

- `apps/macos/KelpieTests/PartitionRegistryTests.swift` (new).
- `apps/macos/KelpieTests/BrowserManagementHandlerTests.swift` — extend with the acceptance test.

## Constraints

- WKWebView only — CEF rejection path must be tested.
- No Keychain. UserDefaults for partition map.
- Respect AGENTS.md macOS button rules — no UI changes that introduce SwiftUI Buttons in WebView windows. Tab name surfaces via existing `TabPillView` text, not a new button.
- Single-file limit 500 lines.

## Verification

- `make lint-swift` passes.
- `tuist generate` then Xcode build succeeds, no warnings.
- Kill any stale Kelpie instance, then launch the new build (project rule).
- Manual acceptance test via CLI:
  - Two partitions, isolated localStorage values.
  - `get-partitions` lists both.
  - `delete-partition` closes the right tabs and removes the store.
- CEF mode: switch engine, verify partition request is rejected with the correct error.
