# Per-Tab Partition + Name — iOS

Parent: [../2026-05-16-per-tab-partition-and-name.md](../2026-05-16-per-tab-partition-and-name.md)

## Pre-conditions

- Shared types from [../per-tab-partition/shared.md](./shared.md) merged.
- `apps/ios/Project.swift` deployment target bumped from 16 to 17.

## Files

### `apps/ios/Project.swift`

Bump `MARKETING_VERSION` per release policy, bump iOS deployment target to 17.0. Regenerate Xcode project with `tuist generate`.

### `apps/ios/Kelpie/Browser/Tab.swift`

Add fields:
```swift
let id: UUID
let webView: WKWebView
var name: String?
var partition: String?
var persistent: Bool   // true unless created with persistent: false
```

`partition` and `persistent` are immutable post-creation (changing them after creation would invalidate the WebView's data store). `name` is mutable — but for this plan we only set it at creation; later rename is a follow-up.

### `apps/ios/Kelpie/Browser/PartitionRegistry.swift` (new)

```swift
@MainActor
final class PartitionRegistry {
    struct Entry {
        let identifier: UUID          // nil-equivalent for non-persistent: not stored
        let persistent: Bool
        var tabCount: Int
        var deleting: Bool
    }
    private var byName: [String: Entry] = [:]
    private var nonPersistentStores: [String: WKWebsiteDataStore] = [:]   // lifetime = live tabs
    private let defaults = UserDefaults.standard
    private let key = "kelpie.partitionRegistry.v1"

    func resolve(partition: String, persistent: Bool) async throws -> WKWebsiteDataStore { … }
    func release(partition: String) async { … }                 // decrement refcount; drop store if non-persistent & count == 0
    func allPartitions() -> [Partition] { … }                    // includes non-persistent live entries; includes orphans as "orphan:<uuid>"
    func delete(partition: String) async throws -> Int { … }     // returns tabsClosed; manages `deleting` flag
    func reconcile() async { … }                                 // runs once at app start, before HTTP server begins serving
    private func persist() { … }                                 // UserDefaults only — no Keychain
}
```

- `resolve` for `persistent: true`: validate via `PartitionValidator`. Throw `PartitionDeleting` if `entry.deleting`. Look up or generate UUID, call `WKWebsiteDataStore(forIdentifier:)`, increment `tabCount`, persist map.
- `resolve` for `persistent: false`: get-or-create from `nonPersistentStores` (a single ephemeral store may back multiple same-name tabs while they live). Tracked in registry but not persisted.
- `delete`: set `entry.deleting = true`; close tabs in partition; `await WKWebsiteDataStore.remove(forIdentifier: entry.identifier)`; drop the entry. New-tab `resolve` for the same name during this window throws `PartitionDeleting`.
- `reconcile` at app start, before the HTTP server accepts requests:
  - Load persisted map; if decode fails, log + start empty.
  - Fetch `WKWebsiteDataStore.fetchAllDataStoreIdentifiers()`.
  - For each map entry: if its UUID is not in the engine set, drop the entry.
  - For each engine UUID not in the map: track as orphan, exposed in `allPartitions()` as `"orphan:<uuid>"` with `tabCount: 0`, `persistent: true`. Can be deleted via `delete-partition` (which strips the `"orphan:"` prefix and removes by UUID).
  - For tabs restored from `SessionStore` referencing a partition name missing from the map: reject the tab restore for that entry, log warning. Do not silently fork the user's identity.
  - Rebuild `tabCount` from the live tab list — never trust the persisted count.

`PartitionValidator.swift` (separate file, mirrors `packages/shared/src/partition.ts` rules exactly): regex `^[A-Za-z0-9._\-]{1,128}$`, must contain alnum, reject `.`, `..`, case-insensitive `default`, reject `ephemeral-` prefix.

### `apps/ios/Kelpie/Browser/TabStore.swift`

Extend `addBrowserTab(url:)` to `addBrowserTab(url:name:partition:persistent:)`:
- If `partition` is set, ask `PartitionRegistry.resolve` for the data store; configure `WKWebViewConfiguration.websiteDataStore` with it.
- If `partition` is nil, use `WebViewDefaults.sharedWebsiteDataStore` (unchanged).
- Store `name`, `partition`, `persistent` on the `Tab`.
- On `closeBrowserTab(id:)`, if tab had a partition, call `PartitionRegistry.release`.

### `apps/ios/Kelpie/Browser/BrowserState.swift`

`WebViewDefaults.sharedWebsiteDataStore` stays — it's the default-container store, still used when no partition is requested. Add no new fields here; partition lifetime lives in `PartitionRegistry`.

### `apps/ios/Kelpie/Browser/SessionStore.swift`

Persist `name`, `partition`, `persistent` per tab. On restart, restore non-`persistent: false` tabs with their original partition.

### `apps/ios/Kelpie/Handlers/BrowserManagementHandler.swift`

- `newTab`: read `body["name"]`, `body["partition"]`, `body["persistent"]` (default true). Validate. Call new `tabStore.addBrowserTab(url:name:partition:persistent:)`. On `PartitionRegistry.InvalidPartition` return `{"success": false, "error": "INVALID_PARTITION"}`.
- `getTabs`: include `name`, `partition`, `persistent` in each tab entry (omit when nil).
- Add `getPartitions(_ body:)` handler returning `PartitionRegistry.allPartitions()`.
- Add `deletePartition(_ body:)` handler:
  1. Find all tabs in partition, call `closeBrowserTab(id:)` for each.
  2. `await partitionRegistry.delete(partition: id)`.
  3. Return `{ success: true, deleted: id, tabsClosed: N }`.

### `apps/ios/Kelpie/Server/Router.swift`

Register `get-partitions` and `delete-partition` routes.

### Tests

- `apps/ios/KelpieTests/PartitionRegistryTests.swift` (new) — unit: resolve/persist/release; UUID stability across `resolve` calls with the same partition name; reject invalid partition strings.
- `apps/ios/KelpieTests/BrowserManagementHandlerTests.swift` — extend existing tests if present; add new-tab with partition, get-partitions, delete-partition, two-tab isolation eval test (the acceptance test from the master plan).

## Constraints

- No Keychain anywhere (project rule). UserDefaults for partition map.
- `WKWebsiteDataStore(forIdentifier:)` only on iOS 17+. With the deployment target bump, we don't need `#available` guards.
- Do **not** alter `NSHTTPCookieStorage` use anywhere — it's a separate cookie jar and isn't part of partition isolation.
- Single-file limit 500 lines.

## Verification

- `make lint-swift` passes.
- `tuist generate` succeeds against the new deployment target.
- Xcode build succeeds, no warnings.
- App launches on iOS 17 simulator; manual two-partition isolation test via CLI passes.
- Acceptance test in `BrowserManagementHandlerTests` passes.
