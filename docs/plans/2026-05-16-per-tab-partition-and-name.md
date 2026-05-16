# Per-Tab Partition and Name

## Problem

Two related gaps in the current tab model:

1. **No tab labelling.** Tabs are identified only by URL/title. There's no human-readable display name an orchestrator can attach to a tab and read back later.
2. **No storage isolation.** All tabs on a device share one website-data-store (iOS `WKWebsiteDataStore.default()`, Android default `Profile`, macOS WKWebView shared store). Two tabs on the same origin cannot hold independent auth state. The Nessie admin simulation needs N independent employee identities on one origin; today this is impossible without one device per employee.

This plan adds two optional fields to new-tab creation — `name` and `partition` — plus partition lifecycle endpoints, and wires the fields through tab listings. Both fields are **optional** and **non-breaking**: existing consumers see no change.

**Important framing — what this plan does and does not deliver:**

- ✅ Delivers: **N independent storage identities on one device.** Each partition is a separate cookie/localStorage/IDB store. Two tabs in the same partition share state; tabs in different partitions are fully isolated.
- ❌ Does not deliver: **N parallel HTTP commands per device.** Same-tab and different-tab requests still serialise on each platform's main actor / UI thread. An orchestrator can keep 12 employee partitions on one device and *drive each in turn*, not all 12 simultaneously. Parallel-different-tab execution is a separate, much larger refactor and is out of scope here.

## Scope

**In scope (this plan):**
- iOS, Android, macOS apps (full feature)
- macOS WKWebView path only
- Shared API types, CLI, MCP layer, docs

**Out of scope (explicit non-goals):**
- Linux app — remains single-tab; `partition` field accepted but rejected with `PARTITION_UNSUPPORTED` if multi-tab orchestration is implied. No new tab routes.
- Windows app — same as Linux.
- macOS CEF renderer path — when `RendererState.activeEngine == .chromium`, new-tab requests with `partition` set return `PARTITION_UNSUPPORTED_ON_CHROMIUM`. CEF partition support is a follow-up that requires extending `native/engine-chromium-desktop`.
- Parallel-different-tabId concurrency on macOS. The platform's `@MainActor` isolation already serialises handler execution; lifting that is a separate body of work. Same-tab requests already serialise.
- Bumping CLI to use partition in group commands.

## API Contract

### POST `/v1/new-tab`

Request:
```json
{
  "url": "https://example.com/",
  "name": "Sam (Engineering Lead)",
  "partition": "sam.eng-lead",
  "persistent": true
}
```

Field semantics:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `url` | string | no | Initial URL (unchanged) |
| `name` | string ≤ 200 chars | no | Free-form display label, surfaced in tab UI and `get-tabs` |
| `partition` | string, 1–128 chars, validator below | no | Storage container identifier. Tabs with the same partition string share storage; different strings are isolated. Omit for default container (back-compat). |
| `persistent` | boolean, default `true` | no | When `false`, partition data is non-persistent (in-memory where supported, deleted-on-close otherwise). Only valid alongside `partition`. |

**Partition string validator** (single source of truth; enforced in CLI, MCP Zod schema, every platform HTTP handler):
- 1–128 ASCII characters
- Character class: `[A-Za-z0-9._\-]`
- At least one alphanumeric character
- Not equal to `.`, `..`
- Not equal to `Default`, `default`, or `DEFAULT` (case-insensitive reserved word — Android `Profile.DEFAULT_PROFILE_NAME`)
- Does not start with `ephemeral-` (reserved internal prefix used by Android non-persistent emulation)

Validator lives in `packages/shared/src/partition.ts` and is mirrored per-platform.

Response (additive — existing fields unchanged):
```json
{
  "success": true,
  "tabId": "550e...",
  "tab": {
    "id": "550e...",
    "url": "https://example.com/",
    "title": "",
    "active": true,
    "name": "Sam (Engineering Lead)",
    "partition": "sam.eng-lead",
    "persistent": true
  },
  "tabCount": 3
}
```

Errors:
- `INVALID_PARTITION` — partition string fails the shared validator (length / charset / reserved word).
- `PARTITION_UNSUPPORTED` — platform / engine cannot honour partition. Response carries diagnostic context so an LLM can recover:
  ```json
  {
    "success": false,
    "error": "PARTITION_UNSUPPORTED",
    "reason": "chromium-engine" | "webview-multi-profile-missing" | "platform-single-tab",
    "activeEngine": "chromium" | "webkit" | null,
    "hint": "switch to webkit via set-engine" | "update Android System WebView to M114+" | "device does not support multiple tabs"
  }
  ```
  Single error code; the `reason` field discriminates the cause. (Earlier draft used `PARTITION_UNSUPPORTED_ON_CHROMIUM` — collapsed into `reason` for one error per machine-actionable failure mode.)
- `PARTITION_DELETING` — `new-tab` with a `partition` that is currently being torn down. Caller may retry.

### `get-tabs` (existing)

Each entry in `tabs[]` gains optional `name` and `partition` fields. Omitted when null.

### POST `/v1/get-partitions` (new)

Request: `{}`.

Response:
```json
{
  "success": true,
  "partitions": [
    { "id": "sam.eng-lead", "tabCount": 2, "persistent": true, "sizeBytes": 1048576 },
    { "id": "morgan.product", "tabCount": 1, "persistent": false }
  ]
}
```

`sizeBytes` is best-effort — omit when the engine cannot report it cheaply (Android `Profile` has no size API).

### POST `/v1/delete-partition` (new)

Request: `{ "id": "sam.eng-lead" }`.

Behaviour: idempotent. On any platform:

1. Mark the partition entry `deleting` in the registry (drops `tabCount`, prevents new resolves for the same id from binding to the old store).
2. Close every tab whose `partition == id`.
3. Await the engine's storage-deletion call (`WKWebsiteDataStore.remove(forIdentifier:)` / `ProfileStore.deleteProfile(name)`).
4. Remove the registry entry permanently.

Concurrent semantics (all handlers run on each platform's main actor / UI thread, so requests serialise):
- Two `delete-partition` calls for the same id: second sees no entry, returns `existed: false` without touching the engine.
- `new-tab` arriving while a delete is mid-flight: registry returns `PARTITION_DELETING`. Caller retries; once delete completes, a new resolve creates a fresh store with a fresh engine-handle (fresh UUID on iOS/macOS, allowed to reuse the same name on Android once `deleteProfile` returns).

Response (consistent shape regardless of whether the partition existed):
```json
{ "success": true, "deleted": "sam.eng-lead", "tabsClosed": 2, "existed": true }
{ "success": true, "deleted": "sam.eng-lead", "tabsClosed": 0, "existed": false }
```

Errors: `PARTITION_IN_USE` only if the engine refuses deletion despite tabs being closed (Android `ProfileStore.deleteProfile` returning false after retry — extreme edge case, surfaced not swallowed).

**HTTP convention note:** Kelpie uses POST + path-named-method for all endpoints. We do *not* use HTTP DELETE / path params, despite the user's draft using `DELETE /v1/partition/{id}`. The functional contract is identical.

## Cross-Platform Mapping

| Concern | iOS | Android | macOS (WKWebView) |
|---|---|---|---|
| Engine API | `WKWebsiteDataStore(forIdentifier: UUID)` | `androidx.webkit.Profile` | Same as iOS |
| Min version | iOS 17 (bump deployment target from 16) | WebView M114+, `MULTI_PROFILE` feature flag | macOS 14 (already met) |
| Partition key type | UUID (we map free-form `partition` → UUID via persisted dictionary) | free-form string (use directly) | UUID (same as iOS) |
| Persisted map storage | `UserDefaults` (no Keychain — project rule) | none needed | `UserDefaults` |
| In-memory mode (`persistent: false`) | `WKWebsiteDataStore.nonPersistent()` (no identifier reuse across launches) | Synthetic profile name, delete-on-tab-close | Same as iOS |
| Default container fallback (no partition) | `WKWebsiteDataStore.default()` (unchanged) | `Profile.DEFAULT_PROFILE_NAME == "Default"` | Same as iOS |
| Enumerate partitions | `fetchAllDataStoreIdentifiers()` ∩ persisted map | `ProfileStore.getAllProfileNames()` minus `"Default"` | Same as iOS |
| Delete partition | `WKWebsiteDataStore.remove(forIdentifier:)` after web view destruction | `ProfileStore.deleteProfile(name)` after `destroy()` | Same as iOS |
| Feature unsupported error | iOS <17 (only if target somehow runs there): n/a after bump | WebView lacks `MULTI_PROFILE` → `PARTITION_UNSUPPORTED` | n/a after macOS 14 baseline |
| Known gotcha | `NSHTTPCookieStorage` is separate from WKWebView (already true) | Static `CookieManager.getInstance()` always operates on Default — must not be used for partitioned tabs | Shared cookie jar (`SharedCookieJar.swift`) must skip partitioned tabs |

## Tab Model Changes

Each platform's tab record gains two fields:

```
Tab {
  id: UUID
  name: String?         // optional display label
  partition: String?    // optional storage container key (null = default)
  persistent: Bool      // true unless explicit persistent: false
  // existing fields unchanged
}
```

Persisted in the platform's existing session-store (iOS `SessionStore.swift`, macOS `SessionStore.swift`, Android equivalent if present) so tabs survive restart. On restart, partitioned tabs rebind to the same partition. Non-persistent tabs are discarded on restart.

## Partition Registry

Each platform owns a `PartitionRegistry`:

- Maps user-facing `partition` string → engine-specific handle (UUID on iOS/macOS, profile-name on Android).
- Tracks per-partition state: `tabCount` (refcount), `persistent`, `deleting` flag.
- Reports `sizeBytes` where cheap.
- Persists the map (UserDefaults / file) so restart finds the same partitions. **No Keychain anywhere** (project rule).
- Validates partition strings against the shared validator above.

A partition string is consistent across CLI/MCP/orchestrators; the engine handle is an implementation detail.

### Registry corruption and reconciliation

The registry is the source of truth for partition→handle mapping. Platforms must define explicit recovery for the failure modes below:

| Scenario | Policy |
|---|---|
| Decode of persisted map fails | Log + recreate empty map. Run reconciliation pass (below). |
| Map entry exists, engine has no matching store (iOS: UUID not in `fetchAllDataStoreIdentifiers()`; Android: name not in `getAllProfileNames()`) | Drop the map entry on startup. |
| Engine has a store with no matching map entry (orphan UUID on iOS) | Expose in `get-partitions` under the synthesised id `"orphan:<uuid>"` so an operator can clean it up via `delete-partition`. |
| Duplicate UUIDs in persisted map | Drop the later duplicate, log warning. (UUID collision is astronomically improbable but corrupted decode could produce one.) |
| Tab restored from session referencing partition that's missing from map | Reject restore for that tab, log warning. Do not silently fork the user's identity by creating a fresh UUID under the same name. |
| `tabCount` drift between restart sessions | Reconciled from live tabs after `SessionStore` load — `tabCount` is rebuilt, never trusted from the persisted map. |

Reconciliation runs once at app launch, on the main actor, before the HTTP server starts accepting requests.

### Non-persistent (in-memory) partitions

- iOS / macOS: `WKWebsiteDataStore.nonPersistent()`. New instance per partition; no persisted map entry.
- Android: emulated. A profile is created with internal name `ephemeral-<partition>-<uuid>`. Deleted-on-close (best effort).
  - **Crash recovery:** at app launch, before reconciliation, enumerate `ProfileStore.getAllProfileNames()` and delete every profile whose name starts with `ephemeral-`. Without this, crashes leak ephemeral profiles to disk indefinitely.
  - The internal `ephemeral-` prefix is reserved by the validator (rejected as a user-supplied partition string).
- Live non-persistent partitions appear in `get-partitions` with `persistent: false` — they exist for the lifetime of their tabs and are surfaced for completeness.

## Concurrency

- All HTTP handlers run on each platform's main actor / UI thread (`@MainActor` on iOS/macOS, single-threaded UI on Android). Same-tab and different-tab requests both serialise.
- New-tab and delete-partition both touch the registry. Both run on the actor. The deletion sequence (mark `deleting` → close tabs → await engine remove → drop entry) all stays on the actor; even though `await` is involved, no other handler can resume mid-sequence because the actor is exclusive — but a *suspension* between `await` points lets a different handler run. The registry's `deleting` flag guards that window.
- The `12 concurrent employee sessions` use case is satisfied as **12 isolated identities**, with the orchestrator issuing commands in turn. If the orchestrator needs literal parallel execution, that's a separate body of work (lifting `@MainActor` from page-bound handlers, or a per-tab actor model) and is explicitly out of scope here.

## CLI / MCP / Shared

- `NewTabRequest` gains `name?`, `partition?`, `persistent?`.
- `TabInfo` gains `name?`, `partition?`, `persistent?`.
- `NewTabResponse.tab` reflects the new `TabInfo`.
- New shared types: `Partition`, `GetPartitionsResponse`, `DeletePartitionRequest`, `DeletePartitionResponse`.
- New CLI commands: `kelpie tab new --name <s> --partition <s> [--non-persistent]`, `kelpie partitions`, `kelpie partition delete <id>`.
- New MCP tools: extend `kelpie_new_tab` schema; add `kelpie_get_partitions`, `kelpie_delete_partition`.
- LLM help (`command-metadata.ts`) updated for all new flags / commands / responses.
- Docs: `docs/api/browser.md`, `docs/cli.md`, `docs/functionality.md`.

## Acceptance Test

End-to-end. Two variants depending on whether the platform's `eval` handler honours `tabId`:

**macOS (handler-side `tabId` routing already in place):**
```
POST /v1/new-tab        { url: "http://localhost:5555/", partition: "alice" }  → tabId tA
POST /v1/new-tab        { url: "http://localhost:5555/", partition: "bob"   }  → tabId tB
POST /v1/eval           { tabId: tA, script: "localStorage.setItem('k','A')" }
POST /v1/eval           { tabId: tB, script: "localStorage.setItem('k','B')" }
POST /v1/eval           { tabId: tA, script: "localStorage.getItem('k')"     }  → "A"
POST /v1/eval           { tabId: tB, script: "localStorage.getItem('k')"     }  → "B"
POST /v1/get-partitions                                                       → contains both
POST /v1/delete-partition { id: "alice" }                                      → tabsClosed: 1, existed: true
POST /v1/get-partitions                                                       → "alice" gone, "bob" remains
```

**iOS / Android (eval handlers operate on the active tab — no per-tab eval today):**
```
POST /v1/new-tab        { url: "http://localhost:5555/", partition: "alice" }  → tabId tA
POST /v1/new-tab        { url: "http://localhost:5555/", partition: "bob"   }  → tabId tB
POST /v1/switch-tab     { tabId: tA }
POST /v1/eval           { script: "localStorage.setItem('k','A')" }
POST /v1/switch-tab     { tabId: tB }
POST /v1/eval           { script: "localStorage.setItem('k','B')" }
POST /v1/switch-tab     { tabId: tA }
POST /v1/eval           { script: "localStorage.getItem('k')" }                 → "A"
POST /v1/switch-tab     { tabId: tB }
POST /v1/eval           { script: "localStorage.getItem('k')" }                 → "B"
… (same partition checks as macOS)
```

Adding per-tab `eval` (and other page-bound handlers) on iOS/Android is the natural follow-up — same shape as the in-flight macOS `macos-tab-targeting-handlers.md` work — but is **explicitly out of scope** for this plan. Tracked as `mobile-tab-targeting-handlers.md` (to be created).

Plus a same-partition coherence test (two tabs created with `partition: "alice"` share a cookie set by the first).

Plus a back-compat test (new-tab without `partition` uses the default store, behaves as today).

Plus a delete-race test (concurrent `delete-partition` + `new-tab` for the same id — the new-tab gets `PARTITION_DELETING`, retry succeeds).

## Per-Platform Sub-Plans

- [iOS](./per-tab-partition/ios.md)
- [Android](./per-tab-partition/android.md)
- [macOS](./per-tab-partition/macos.md)
- [Shared (CLI / MCP / types / docs)](./per-tab-partition/shared.md)

## Implementation Sequence

1. Land shared types + CLI + MCP + docs ([shared sub-plan](./per-tab-partition/shared.md)) — small, types-only, unblocks all three platforms.
2. In parallel, three Opus agents implement iOS / Android / macOS in dedicated git worktrees under `.worktrees/`.
3. Each platform branch lands its acceptance test (eval + isolation check) and platform lint/build/tests pass.
4. Integration: merge platform branches in sequence, resolve trivial conflicts (only TabInfo extensions touch shared code), run cross-platform e2e via the CLI.
5. GitHub release per Kelpie release policy.

## Cross-Provider Review

Parallel adversarial review run 2026-05-16: `superpowers:code-reviewer` (Claude) + `codex exec` (Codex). Both reviewers operated independently against the plan files as written. Convergent findings — both reviewers raised the same point — are marked **[CONVERGENT]**. All accepted findings have been resolved in-place above; this section records what changed and why.

### Resolved findings

1. **[CONVERGENT, CRITICAL] macOS `SharedCookieJar` cross-tab cookie propagation.** `apps/macos/Kelpie/Handlers/HandlerContext.swift:459-562` actively syncs cookies across all WKWebView tabs via `~/.kelpie/session/cookies.json`. Partitioned tabs would write into the shared jar and have other tabs' cookies pushed back. **Resolved:** macOS sub-plan now states that partitioned tabs are excluded from `SharedCookieJar` participation — `persistRendererCookiesToSharedJar`, `syncSharedCookiesIntoRenderer`, and the cookie handlers (`allCookies`, `setCookie`, `deleteCookie`, `deleteAllCookies`) must early-return for any tab whose `partition != nil`, operating on that tab's own `websiteDataStore.httpCookieStore` directly.

2. **[CONVERGENT, HIGH] "12 concurrent employee sessions" oversold.** Plan delivers isolated identities, not parallel command execution. **Resolved:** Master plan opens with an explicit "Important framing" section distinguishing isolation from parallelism, and the Concurrency section spells out the serialised model. `docs/functionality.md` will state the same.

3. **[CONVERGENT, HIGH] `delete-partition` deletion race.** `WKWebsiteDataStore.remove(forIdentifier:)` is `async`; between the `await` and completion, another handler call can land on the main actor and try to bind a new tab to the same partition. **Resolved:** Registry now has a `deleting` flag set before any await; `new-tab` for a deleting partition returns `PARTITION_DELETING` and the caller retries. Spelled out in API Contract → POST `/v1/delete-partition`.

4. **[CONVERGENT, HIGH] `delete-partition` response shape contradicted itself.** Earlier draft had `deleted: 0` and `deleted: <id>` in different places. **Resolved:** Always returns `{ deleted: <requested-id>, tabsClosed: N, existed: bool }`. Shared TypeScript type `DeletePartitionResponse` updated in sub-plan.

5. **[CONVERGENT, HIGH] iOS UUID map has no corruption/recovery rules.** **Resolved:** New "Registry corruption and reconciliation" table in the Partition Registry section spells out policy for every failure mode (decode fail, missing UUID, orphan store, duplicate UUIDs, tab restored against missing map entry, tabCount drift).

6. **[CONVERGENT, HIGH] `get-partitions` enumeration inconsistency.** Intersecting `fetchAllDataStoreIdentifiers()` with the persisted map omits live non-persistent partitions and hides orphaned stores. **Resolved:** Registry now defined as the source of truth; reconciliation pass at startup prunes dangling map entries and surfaces orphans as `"orphan:<uuid>"`. Live non-persistent entries are included in `get-partitions` for visibility.

7. **[CONVERGENT, HIGH] Android ephemeral profiles leak across crashes.** Without sweep, every crash mid-session leaves an `ephemeral-*` profile on disk forever. **Resolved:** Android plan adds startup sweep that enumerates `ProfileStore.getAllProfileNames()` and deletes every profile whose name starts with `ephemeral-` before the HTTP server accepts requests. The prefix is reserved by the shared validator.

8. **[CONVERGENT, MEDIUM] Partition validator was prose-only, allowed reserved/profile-internal hazards.** **Resolved:** Validator is now a concrete spec (length, charset, must contain alnum, rejects `.`/`..`/`Default` case-insensitive/`ephemeral-` prefix). Single source of truth in `packages/shared/src/partition.ts`, enforced everywhere (CLI, MCP Zod, every platform handler).

9. **[CONVERGENT, MEDIUM] `PARTITION_UNSUPPORTED_ON_CHROMIUM` not discoverable to LLMs.** **Resolved:** Collapsed into single `PARTITION_UNSUPPORTED` error with `reason` discriminator, `activeEngine` diagnostic, and machine-actionable `hint`. Documented in `docs/api/browser.md` and LLM help.

10. **[CODEX-ONLY, CRITICAL] Acceptance test assumed per-tab `eval` works on iOS/Android.** Verified against exploration data: iOS and Android handlers operate on the *active* tab; they don't honour `tabId` yet (that's the in-flight `macos-tab-targeting-handlers.md` work, macOS-only). **Resolved:** Acceptance test split into two variants — macOS uses `tabId`, mobile uses `switch-tab` + `eval`. Adding per-tab routing to mobile handlers is tracked as a separate follow-up plan.

### Findings not adopted

None. All findings either resolved or already explicit policy.

### Findings outside review scope (deferred)

- **macOS-CEF partition support.** Already explicit non-goal in the plan; both reviewers asked only about error discoverability, which is now resolved.
- **iOS/Android per-tab handler routing.** Identified as the natural follow-up to make the acceptance test cleaner; tracked separately, not blocking this plan.
- **Parallel different-tab command execution.** The original spec demanded it; both reviewers confirmed this plan does not deliver it. Tracked as a separate, larger refactor (`per-tab-actor-model.md`, to be written if/when needed).
