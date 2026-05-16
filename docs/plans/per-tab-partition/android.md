# Per-Tab Partition + Name — Android

Parent: [../2026-05-16-per-tab-partition-and-name.md](../2026-05-16-per-tab-partition-and-name.md)

## Pre-conditions

- Shared types from [./shared.md](./shared.md) merged.
- `androidx.webkit:webkit:1.10.0` already on classpath (confirmed). No upgrade needed.

## Feature gating

At runtime, check `WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)` once at app start.

- Supported (Android System WebView M114+): full feature.
- Unsupported: `new-tab` with `partition` returns `{"success": false, "error": "PARTITION_UNSUPPORTED"}`. `get-partitions` returns `{ partitions: [] }`. `delete-partition` returns the same error.

Log the gate result at startup so debugging is easy.

## Files

### `apps/android/app/src/main/java/com/kelpie/browser/browser/BrowserTab.kt`

Add fields:
```kotlin
data class BrowserTab(
    val id: String,
    val webView: WebView,
    var name: String? = null,
    var partition: String? = null,   // null = Default profile
    var persistent: Boolean = true,
    val isStartPage: Boolean,
    var currentUrl: String,
    var pageTitle: String,
    var isLoading: Boolean,
)
```

### `apps/android/app/src/main/java/com/kelpie/browser/browser/PartitionRegistry.kt` (new)

```kotlin
class PartitionRegistry(private val context: Context) {
    data class Entry(
        val name: String,
        val persistent: Boolean,
        var tabCount: Int,
        var deleting: Boolean,
    )

    private val entries = mutableMapOf<String, Entry>()
    private val supported: Boolean by lazy {
        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
    }

    suspend fun reconcile() { … }                              // run at app start, before HTTP server begins serving
    fun resolveProfileName(partition: String, persistent: Boolean): String { … }
    fun release(partition: String) { … }
    fun allPartitions(): List<Partition> { … }
    suspend fun delete(partition: String): Int { … }            // returns tabsClosed
}
```

Mapping:
- `persistent: true`: profile name = the partition string itself (Android allows free-form names).
- `persistent: false`: profile name = `"ephemeral-" + partition + "-" + uuid()`. **Internal-only**; the partition string the orchestrator sees stays the user-supplied one. Best-effort delete-on-close — data is written to disk during the session (document in `functionality.md`).
- `delete`: set `entry.deleting = true`; close any remaining tabs in the partition; call `ProfileStore.getInstance().deleteProfile(name)`. If it returns false, retry once after a UI-thread tick; if still false, surface as `PARTITION_IN_USE`. Drop the entry on success.

Validation mirrors `packages/shared/src/partition.ts` rules exactly — reject `"Default"` (and `"default"` / `"DEFAULT"` case-insensitive), `.`, `..`, and the `ephemeral-` prefix.

### Startup ephemeral sweep (CRITICAL — prevents crash-leak)

At app start, before `reconcile` and before the HTTP server begins serving:

```kotlin
if (WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
    val store = ProfileStore.getInstance()
    store.getAllProfileNames()
        .filter { it.startsWith("ephemeral-") }
        .forEach { store.deleteProfile(it) }   // log + ignore false (rare)
}
```

Without this sweep, every crash mid-session leaks one or more `ephemeral-*` profiles to disk indefinitely.

### Reconciliation policy

- Persist map is `kelpie.partitionRegistry.v1` in shared prefs.
- On decode fail: log + start empty.
- For each map entry: if profile name not in `ProfileStore.getAllProfileNames()`, drop entry.
- For each profile name not in map (excluding `"Default"` and `ephemeral-*` which the sweep cleared): expose in `allPartitions()` with `tabCount: 0`, `persistent: true`. Operator can `delete-partition` to clean up.
- Tabs restored from `SessionStore` referencing a missing partition name: reject restore, log warning.
- `tabCount` rebuilt from live tabs after restore — never trust the persisted count.

### `apps/android/app/src/main/java/com/kelpie/browser/browser/TabStore.kt`

Extend `createTab` / `addTab`:
- Accept `name`, `partition`, `persistent`.
- If partition set and `MULTI_PROFILE` supported, resolve profile name via `PartitionRegistry`, call `WebViewCompat.setProfile(webView, profileName)` **before** the first `loadUrl`.
- If partition set and `MULTI_PROFILE` unsupported, throw a typed error caught by the handler and surfaced as `PARTITION_UNSUPPORTED`.
- Store `name`/`partition`/`persistent` on the `BrowserTab`.
- On close, call `PartitionRegistry.release`.

### `apps/android/app/src/main/java/com/kelpie/browser/handlers/BrowserManagementHandler.kt`

- `newTab(body)`: read `name`, `partition`, `persistent`. Validate. Call `tabStore.addTab(...)`. Map registry errors to API errors.
- `getTabs(body)`: include `name`, `partition`, `persistent` per tab (omit when null).
- Add `getPartitions(body)`.
- Add `deletePartition(body)`.
- Existing global `CookieManager.getInstance()` callers must **not** be invoked for partitioned tabs — they target the Default profile and would corrupt isolation. Audit `ChromeAuthHelper.kt` and route any partitioned-tab cookie reads through `WebViewCompat.getProfile(webView).cookieManager`.

### `apps/android/app/src/main/java/com/kelpie/browser/server/Router.kt` (or equivalent)

Register `get-partitions` and `delete-partition` routes.

### Tests

- `apps/android/app/src/test/java/com/kelpie/browser/browser/PartitionRegistryTest.kt` (new).
- `apps/android/app/src/androidTest/java/com/kelpie/browser/handlers/BrowserManagementHandlerTest.kt` — extend with the acceptance test from the master plan, executed against a real WebView via Espresso/instrumentation.

## Constraints

- `WebViewCompat.setProfile` is `@UiThread` — call it from the main thread before first `loadUrl`.
- Do not call `CookieManager.getInstance()` for partitioned tabs.
- Single-file limit 500 lines.
- ktlint must pass.

## Verification

- `cd apps/android && ./gradlew build` succeeds (includes ktlint).
- Instrumentation test passes the two-partition isolation acceptance test on an Android 14 emulator with Chrome WebView M114+.
- On a device/emulator without `MULTI_PROFILE`, `new-tab` with `partition` returns `PARTITION_UNSUPPORTED` cleanly.
