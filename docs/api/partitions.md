# Kelpie API — Storage Partitions

Per-tab storage isolation: `get-partitions`, `delete-partition`, and the
`partition` / `persistent` fields on `new-tab`.

For protocol details, errors, and MCP tool names, see [README.md](README.md).
For the rest of the tab lifecycle, see [browser.md](browser.md).

---

## Partitions

A partition is an isolated cookie / localStorage / IndexedDB container. It
exists implicitly from the moment the first tab is created with that
`partition` string, and is destroyed by `delete-partition` (or, for
non-persistent partitions, when its last tab closes).

**Isolation, not parallelism.** N partitions give one device N independent
storage identities. They do **not** give N parallel command streams — handlers
still serialise on each platform's main thread, so an orchestrator drives each
partition in turn.

**Platform support:** macOS on the WebKit engine, and Windows on the Chromium
(CEF) engine. macOS on the Chromium engine, iOS, Android, and Linux return
`PARTITION_UNSUPPORTED`.

### Partition errors

| Code | HTTP | When |
|---|---|---|
| `INVALID_PARTITION` | 400 | The partition string fails the shared validator. |
| `PARTITION_UNSUPPORTED` | 501 | The platform or engine cannot honour partitions. |
| `PARTITION_DELETING` | 409 | `new-tab` named a partition that is mid-teardown. Retry. |
| `PARTITION_IN_USE` | 409 | The engine refused deletion even after every tab was closed. The id is freed anyway and the abandoned store is relisted as `orphan:<uuid>`. |
| `ENGINE_SWITCH_BLOCKED_BY_PARTITION` | 409 | `set-renderer` to `chromium` was called while partitioned tabs are open. |

`PARTITION_UNSUPPORTED` carries diagnostic context so a caller can recover
without guessing. A single error code with a `reason` discriminator:

```json
{
  "success": false,
  "error": {
    "code": "PARTITION_UNSUPPORTED",
    "message": "...",
    "reason": "chromium-engine",
    "activeEngine": "chromium",
    "hint": "switch to webkit via set-renderer"
  }
}
```

| `reason` | Platform | Recovery |
|---|---|---|
| `chromium-engine` | macOS running CEF | `set-renderer` with `{"engine": "webkit"}`, then retry. |
| `webview-multi-profile-missing` | Android | Update Android System WebView to M114 or later. |
| `platform-single-tab` | iOS, Linux | Not available; use a macOS or Windows device for partitioned work. |

### `getPartitions`
List live partitions.

```json
POST /v1/get-partitions
{}

Response:
{
  "success": true,
  "partitions": [
    {"id": "sam.eng-lead", "tabCount": 2, "persistent": true},
    {"id": "morgan.product", "tabCount": 1, "persistent": false}
  ]
}
```

The first `new-tab` in a session fixes a partition's persistence. A later tab
naming the same `partition` joins the existing store and reports the existing
`persistent` value even if it asked for the other one — two tabs in one
partition must share storage, and a store cannot be on disk for one and in
memory for the other. `get-tabs` always reports what the tab actually got.

`tabCount` is rebuilt from the live tab list, never trusted from persisted
state. `sizeBytes` is best-effort and omitted when the engine cannot report it
cheaply — neither macOS WebKit nor Windows Chromium has a cheap size API, so
both always omit it.

Non-persistent partitions appear here with `persistent: false` for the lifetime
of their tabs.

Orphaned stores — an engine-level data store with no registry entry, which a
crash or a partial uninstall can leave behind — are surfaced under the
synthesised id `orphan:<uuid>` so an operator can clean them up with
`delete-partition`.

### `deletePartition`
Close every tab bound to a partition, then remove its data store.

```json
POST /v1/delete-partition
{"id": "sam.eng-lead"}

Response (partition existed):
{"success": true, "deleted": "sam.eng-lead", "tabsClosed": 2, "existed": true}

Response (unknown id — still a success):
{"success": true, "deleted": "sam.eng-lead", "tabsClosed": 0, "existed": false}
```

`deleted` always echoes the requested id. The call is idempotent: a second
delete for the same id returns `existed: false` without touching the engine.

The teardown sequence is: mark the partition `deleting`, close its tabs, await
the engine's storage removal, then drop the registry entry. While the flag is
set, a `new-tab` naming the same partition fails with `PARTITION_DELETING`
rather than binding to a store that is about to disappear. Once the delete
returns, a retry creates a fresh store under a fresh engine handle.

### Windows (Chromium/CEF)

Windows maps one partition onto one `CefRequestContext`. A persistent partition
gets `CefRequestContextSettings.cache_path = <profile>/partitions/<id>`; a
non-persistent one is created with an empty `cache_path`, which is CEF's
in-memory context — the data never reaches the disk. A tab with no `partition`
is created with a null request context, which is the global store every
ordinary Chrome tab shares. Cookies, `localStorage`, IndexedDB, and the HTTP
cache all follow the context, so `get-cookies` / `set-cookie` and `evaluate`
are partition-scoped without any special casing.

`window.open` inherits the opener's context. Windows cancels the CEF popup and
reopens the target as one of its own tabs, so the opener's partition is copied
onto the new tab explicitly — an isolated tab cannot open its way out of its
partition.

Each tab's `name` and `partition` are recorded in the Windows session snapshot
(`session.json`) and rebound on restore, so a persistent partition's logins
survive a restart. The snapshot parser is strict: a snapshot carrying a
partition string the shared validator would reject is discarded whole rather
than restored into the default store.

`delete-partition` marks the partition deleting, force-closes its tabs, waits
for CEF to report every `OnBeforeClose`, releases the context, and then removes
the directory. If Chromium still holds file handles, the directory is renamed
to `<profile>/partitions/.trash/<id>-<epoch>` and purged on the next launch;
the call then returns `PARTITION_IN_USE` rather than a success that left the
data in place. The id is freed either way, and the response carries the honest
`tabsClosed` and `existed` values alongside the error.

Deleting the partition that owns every open tab leaves a fresh `about:blank`
tab in the default store, the same rule `close-tab` follows.

### Cookie endpoints and partitioned tabs

macOS syncs cookies between WebKit tabs and the Chromium renderer through a
shared cookie jar. Partitioned tabs are excluded from that sync entirely —
otherwise every partition would leak its cookies into the shared jar and
receive every other tab's cookies back. `get-cookies`, `set-cookie`, and
`delete-cookies` targeting a partitioned tab operate directly on that tab's own
cookie store.

These two paragraphs are macOS-specific. Windows has a single engine and no
shared cookie jar to leak into, so neither the exclusion nor the engine-switch
block applies there.

For the same reason, `set-renderer` to `chromium` is **rejected** with
`ENGINE_SWITCH_BLOCKED_BY_PARTITION` while any partitioned tab is open:
partitioned WebKit stores cannot be losslessly migrated into CEF's single
browser. Close or delete the partitions first. Switching back to `webkit` is
always allowed, so a session that restored partitioned tabs under Chromium can
still reach the engine those tabs need.

### `switchTab`
Switch the active tab by UUID.

```json
POST /v1/switch-tab
{"tabId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "windowId": "<uuid>"}  // windowId optional

Response:
{
  "success": true,
  "tab": {"id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "windowId": "<uuid>", "url": "https://example.com/about", "title": "About", "active": true},
  "windowId": "<uuid>"
}
```

### `closeTab`
Close a tab by UUID.

```json
POST /v1/close-tab
{"tabId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8", "windowId": "<uuid>"}  // windowId optional

Response:
{
  "success": true,
  "closed": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "tabCount": 1,
  "windowId": "<uuid>"
}
```

If the last tab is closed, a new blank tab replaces it — `tabCount` will be `1`, not `0`.
