# Peer-to-peer cookie sync

**Status:** Design, revised after cross-provider review (see the end).

## Goal

When a person is signed in to Kelpie with UOA, every Kelpie on the same local
network that is signed in to the same UOA account keeps one shared set of
default-store cookies. A login, cookie change or logout on one device reaches the
others within seconds while both are running. Agents connected over MCP to any
device can read every cookie, including HttpOnly ones, and copy them into an
isolated tab or back into the default store.

Platforms: macOS (WebKit and Chromium), iOS, Android, Windows, Linux.

## Decisions already made

- **Same network only.** Devices talk directly over the LAN. No relay, no
  rendezvous server, no TURN and no Kelpie backend. A device that was away
  catches up when it next shares a network with another signed-in Kelpie.
- **No server ever stores or sees cookies.** UOA is used only to prove that two
  devices belong to the same account, through the existing
  `/oauth/kelpie/pair` and `/oauth/kelpie/pair/validate` endpoints
  ([account pairing](../api/account-pairing.md)). The proof is bound to the
  encrypted channel, so UOA learns nothing about cookies.
- **Default store only.** Partitioned (isolated) tabs never sync, never receive
  synced cookies and never contribute to the sync. Copying into or out of an
  isolated tab happens only when an agent explicitly asks for it.
- **Automatic.** Sync starts on sign-in and stops on sign-out or account change.
  There is no toggle and no new UI.
- **Standalone apps only.** Embedded browser sessions inside a containing app do
  not run the sync service.

## Platform facts that shape the design

| Fact | Consequence |
|---|---|
| iOS suspends backgrounded apps and their sockets. | iOS syncs in the foreground, flushes pending pushes in a short background task and restarts its listener on return. It cannot sync while suspended. |
| Android keeps its server alive in a foreground service. | Android syncs in the background while that service runs. |
| Android `CookieManager` cannot enumerate cookies. `CookieManagerCompat.getCookieInfo(url)` (androidx.webkit, `GET_COOKIE_INFO`) returns full `Set-Cookie` strings for the cookies that would be sent to one URL. | Android scans a list of exact URLs and core-sync treats only the entries those URLs would return as observed. WebViews without `GET_COOKIE_INFO` report sync as unsupported. The pinned androidx.webkit 1.10.0 must be bumped. |
| Windows and Linux bind automation to loopback, advertise nothing and have no mDNS code in use. | Sync uses a **separate, sync-only listener** on LAN interfaces with new mDNS advertising and browsing. Automation stays loopback-only. |
| CEF cookie access today goes through a tab's DevTools session, which sees only the current page. | Sync reads and writes the global store through `CefCookieManager` (`VisitAllCookies`, `SetCookie`, `DeleteCookies`), which needs no tab and handles HttpOnly. |
| No platform browses mDNS or requests a pairing ticket today; no platform has ECDH or HKDF code. | All three are new on every platform. |
| macOS has a second cookie writer: `SharedCookieJar` pushes a JSON file into the live store every 2 s. | Retired while sync owns the default store. See [macOS](#macos). |
| Session cookies (no expiry) do not survive an app restart. | A restart must not look like a logout. See [Lifecycle rules](#lifecycle-rules). |

## Architecture

```
            same UOA account, same LAN
 ┌─────────────────────┐          ┌─────────────────────┐
 │ Kelpie A            │  mDNS    │ Kelpie B            │
 │  Cookie adapter ◄─┐ │◄────────►│ ┌─► Cookie adapter  │
 │  core-sync store  │ │ AES-GCM  │ │   core-sync store │
 │  Sync client  ────┼─┼─────────►│ └── Sync listener   │
 └─────────┬───────────┘ requests └──────────┬──────────┘
           │ ticket issue / validate (TLS)   │
           └──────────────► UOA ◄────────────┘
                  (sees only a 32-byte transcript hash)
```

Per device:

- **core-sync** (new shared C++ module in `core/native/core-sync`, C API for
  Swift and JNI, linked directly by Windows and Linux): cookie canonicalisation,
  the metadata store, the hybrid logical clock, merge, change feed, message
  validation and the handshake transcript. One implementation for all five
  platforms, so merge behaviour cannot drift.
- **Platform pieces**: cookie adapter, crypto, account bridge, sync listener,
  mDNS advertising and browsing, and the sync service that drives them. See
  [Platform contract](#platform-contract).

## Discovery

- Service type **`_kelpie-sync._tcp`**, separate from `_kelpie._tcp`, so the CLI
  never mistakes a sync listener for an automation API. iOS and macOS list it in
  `NSBonjourServices`.
- The listener binds an ephemeral port. It accepts a connection only when the
  peer address is loopback, IPv4/IPv6 link-local, or inside the directly
  connected subnet of an eligible interface. Eligible interfaces are physical
  Wi-Fi and Ethernet; VPN, tunnel, point-to-point and cellular interfaces are
  excluded. Outgoing connections apply the same rule to resolved addresses and
  prefer IPv4 and link-local.
- TXT record: `v=1`, `id=<replicaId>`, `h=<accountHint>`.
  - `replicaId`: 16 random bytes, base64url, **new on every launch and every
    sign-in**. It names this run of this store. It is never persisted, so backup
    and restore cannot clone it and it cannot track a device across launches.
  - `accountHint`: first 8 bytes, base64url, of
    `SHA-256("kelpie-sync-hint-v1" || 0x00 || subject || 0x00 || UTC date)`.
    It only saves UOA calls in an office full of Kelpie users; it is public and
    authorises nothing.
  - Browsing and the responder both accept the hints for yesterday, today and
    tomorrow (UTC). The advertisement refreshes when the UTC date changes.
- Advertising and browsing run only while signed in. Sign-out, account change and
  iOS backgrounding stop both.
- **One session per pair.** The device with the lexicographically smaller
  `replicaId` initiates. The other initiates only if no session has formed 15 s
  after it saw the peer, which covers a listener blocked by a firewall. The
  initiator is the only side that sends requests.

## Handshake and channel

All sync endpoints are `POST` with `Content-Type: application/json`. Requests with
an `Origin` header, `Transfer-Encoding` or duplicate `Content-Length` are
rejected. Responses carry `Cache-Control: no-store`.

| Limit | Value |
|---|---|
| `hello` and `auth` body | 16 KiB, read deadline 5 s |
| `exchange` body | 4 MiB, accepted only with a live `X-Kelpie-Sync-Session` header checked before the body is read |
| `hello` rate | 10/min per source address, 60/min in total |
| Pending handshakes | 8; a new one evicts the oldest |
| Outgoing handshakes | 10/min in total; per-peer exponential backoff from 5 s to 5 min after a failure |
| Concurrent UOA calls | 2 |

### 1. `POST /v1/sync/hello` (unauthenticated)

```json
{ "v": 1, "replica": "…", "hint": "…", "now": 1731150000000,
  "platform": "macos", "name": "Studio Mac",
  "key": "<P-256 public key, x9.63 uncompressed, base64url>", "nonce": "<32 bytes base64url>" }
```

The responder refuses, before any UOA call:

- an unknown `v`, a malformed field or a key that is not a valid P-256 point;
- a hint outside its accepted set: `409 {"error":"ACCOUNT_MISMATCH"}`;
- a clock difference over 2 minutes: `409 {"error":"CLOCK_SKEW"}`, also shown in
  status.

Otherwise it creates a pending handshake (in memory, 60 s TTL) and replies with
its own `replica`, `now`, `platform`, `name`, `key`, `nonce`, a 32-byte
`handshakeId` and `expiresAt`. The initiator applies the same skew check.

Both sides compute the transcript hash:

```
T = SHA-256("kelpie-sync-v1" || 0x00 || initiatorReplica || 0x00 || initiatorKey ||
            0x00 || initiatorNonce || 0x00 || responderReplica || 0x00 ||
            responderKey || 0x00 || responderNonce)
challenge = base64url(T)            // 43 chars, UOA's challenge format
```

### 2. Mutual UOA proof

Each side asks UOA for a ticket over the same transcript with a role-specific
client id, using its own session (scope `kelpie.connect`):

- initiator: `POST /oauth/kelpie/pair {challenge, clientId:"kelpie-sync:i:<initiatorReplica>"}`
- responder: `POST /oauth/kelpie/pair {challenge, clientId:"kelpie-sync:r:<responderReplica>"}`

### 3. `POST /v1/sync/auth`

```json
{ "handshakeId": "…", "ticket": "<initiator ticket>" }
```

The first `/auth` for a `handshakeId` **consumes** the pending handshake,
whatever the outcome; a second one gets `401 {"error":"SYNC_SESSION"}`. The
responder validates the initiator's ticket with its own UOA session:
`/oauth/kelpie/pair/validate {ticket, challenge, clientId:"kelpie-sync:i:<initiatorReplica>"}`.
Only `{active:true}` continues. It then returns its own ticket and installs the
session keys exactly once:

```json
{ "ticket": "<responder ticket>", "sessionExpiresAt": 1731150600000 }
```

The initiator validates that ticket the same way with the responder's client id
and installs its keys. Either failure ends the attempt; a retry starts again from
`hello` with new keys. Neither device receives a spendable UOA credential.

**Why a man in the middle fails.** Swapping keys creates two transcripts. A ticket
UOA issued for one fails validation against the other, and the attacker cannot get
a ticket for the account without its credentials. Role prefixes stop a ticket
being reflected back to its issuer.

### 4. Session keys

```
Z    = ECDH(own private key, peer public key)
i2r  = HKDF-SHA256(ikm=Z, salt=T, info="kelpie-sync-v1 i2r", 32 bytes)
r2i  = HKDF-SHA256(ikm=Z, salt=T, info="kelpie-sync-v1 r2i", 32 bytes)
```

Ephemeral keys are discarded after derivation. A session lasts 10 minutes, or
until sign-out, account change, iOS backgrounding or either side's restart.
A new session needs a new handshake and fresh UOA proofs, so revoking the UOA
session cuts sync off within 10 minutes. UOA downtime blocks new sessions and
never falls back to an unauthenticated mode.

### 5. Encrypted exchange

`POST /v1/sync/exchange`, header `X-Kelpie-Sync-Session: <handshakeId>`:

```json
{ "seq": 7, "box": "<base64url ciphertext||16-byte tag>" }
```

- Only the initiator sends requests. Requests are sealed with `i2r`, responses
  with `r2i`. Both use nonce = 4 zero bytes || 64-bit big-endian request `seq`,
  so a nonce never repeats under one key.
- AAD = `"kelpie-sync-v1" || 0x00 || sessionId || 0x00 || ("req"|"res") || seq`.
- The initiator numbers requests from 1 and may have a pull and a push in flight
  at once. The responder keeps a 64-entry replay window: it accepts a `seq` it has
  not seen that is no more than 64 below the highest seen.
- An unknown or expired session returns `401 {"error":"SYNC_SESSION"}` and the
  initiator handshakes again. Responses are never cached or replayed.

## Data model

### Cookie identity and wire shape

The key is the JSON array `["<domain>","<path>","<name>"]`, so no delimiter can
make two cookies collide.

| Field | Rule |
|---|---|
| `domain` | Lower-case. Domain cookies start with `.`; host-only cookies do not. |
| `path` | As stored, default `/`. |
| `name`, `value` | Exact bytes; name + value at most 4 KiB. |
| `expires` | Whole Unix seconds, or `null` for a session cookie. |
| `secure`, `httpOnly` | Booleans. |
| `sameSite` | `"Strict"`, `"Lax"`, `"None"` or `"Unspecified"` (attribute absent). An adapter that cannot tell must skip the cookie; unknown never becomes a default. |

Not synced: cookies for loopback hosts (`localhost`, `*.localhost`,
`127.0.0.0/8`, `::1`); cookies the engine marks as partitioned (CHIPS); anything
in a partitioned tab's store. Each adapter documents whether its enumeration API
exposes partitioned cookies at all.

### Metadata store

One file per device: `<app data>/Kelpie/sync/cookie-sync.json` (Android
`filesDir`, Windows and Linux the profile directory). 0600, atomic
temp-write-fsync-rename, excluded from iCloud/iTunes and Android Auto Backup, no
Keychain. It holds no cookie values.

```
file    = { v, subject, lastHlc, entries[] }
entry   = { domain, path, name,
            hlc: [wall, counter, replica],     // version of the accepted record
            deleted,
            attrs: { expires, secure, httpOnly, sameSite },   // accepted record
            valueHash,                          // SHA-256 of the accepted value
            observed,                           // engine fingerprint, or "absent"
            unapplied,                          // engine refused the accepted record
            localOnly }                         // belongs to a different account
```

- **Accepted record vs observed engine state.** `attrs` and `valueHash` describe
  the record this device accepted. `observed` is the fingerprint of what this
  device's engine actually holds. Forwarding sends the accepted attributes with
  the engine's value, only when that value's hash equals `valueHash`. One version
  therefore always carries one record, whichever device forwards it.
- **`unapplied`**: the engine refused or reshaped a remote record. The entry
  keeps the remote version and records the engine's real state in `observed`.
  A later scan that finds the same engine state changes nothing; only a genuine
  engine change becomes a local edit. Unapplied sets are not forwarded (the
  origin still has them); unapplied tombstones are.
- **`localOnly`**: never forwarded, never tombstoned; any remote version wins and
  clears it. A local change keeps it set. The entry is dropped when the cookie
  disappears.
- **Tombstones are kept indefinitely**, capped at 20 000; beyond that the oldest
  by version are removed. Time alone never proves every peer has seen a deletion.
- **Subject binding.** The file records the UOA subject it belongs to. Opening it
  under another subject resets the entries and marks every cookie already in the
  store as `localOnly`, so one person's sessions never reach another person's
  devices. With no file at all (the first sign-in on a device), cookies already in
  the store get the zero version `(0, 0, replica)`: any real peer version beats
  them, and cookies no peer has still propagate.

### Hybrid logical clock

`hlc = (wall ms, counter, replicaId)`, ordered in that order. A local stamp uses
`wall = max(now, lastHlc.wall)` and increments `counter` when `wall` is unchanged.
Merging a newer remote stamp advances `lastHlc`. The 2-minute skew gate at
`hello` keeps peers' clocks close; there is no other clock rule, because ignoring
records would break convergence.

### Merge (remote record R for key K)

| Local entry | Result |
|---|---|
| none | apply R |
| `localOnly` | apply R |
| older than R | apply R |
| equal to or newer than R | ignore |

Applying is a transaction on the store's serial executor: plan, write to the
engine, read back, commit. No scan runs inside it. Commit:

| Engine after the write | Entry becomes |
|---|---|
| set, and K reads back | R's version, attrs and `valueHash`; `observed` = read-back fingerprint |
| set, but K is missing (refused, evicted or stored under another key) | R's version, `unapplied`, `observed` = "absent" |
| delete, and K is gone | tombstone with R's version, `observed` = "absent" |
| delete, but K remains | tombstone with R's version, `unapplied`, `observed` = K's fingerprint |

If the read-back finds the same name under a different domain or path (for
example host-only instead of a domain cookie), that variant becomes a
`localOnly` entry with its fingerprint. It is never forwarded, so it cannot start
a delete-and-recreate loop between engines.

Every remote version is final the moment it is committed; the merge is
commutative and idempotent, so changes forwarded through a third device converge.

### Caps

The synced set is held below the smallest engine's limits (Chromium: 180 per
domain, about 3 300 in total). A remote set that would give a domain more than
150 cookies, or the store more than 3 000, is ignored and counted in status. That
keeps a full WebKit store from making a CEF device evict cookies.

### Local change detection (scan)

A scan passes the engine's cookies and its **coverage**:

- `{"all":true}` — only from a full-store enumeration (WebKit `getAllCookies`,
  CEF `VisitAllCookies`). A partial read is never reported as `all`.
- `{"urls":[…]}` — Android. core-sync counts an entry as observed only if RFC 6265
  matching (domain match, path match, `Secure` needs https) would return it for
  one of those URLs. A failed query aborts the scan; it never becomes an empty
  result.

For each observed key:

| Engine | Entry | Result |
|---|---|---|
| present | none | new entry, stamped now (zero version or `localOnly` on the first scan after a reset, see above) |
| present, fingerprint = `observed` | any | nothing |
| present, fingerprint ≠ `observed` | normal | local edit, stamped now |
| present, fingerprint ≠ `observed` | `localOnly` | refresh `observed`, stay `localOnly` |
| absent | `observed` = "absent" | nothing |
| absent | `localOnly` | drop the entry |
| absent | live, `expires` passed | drop the entry; every device expires it |
| absent | live, not expired | deletion candidate |

Deletion candidates become tombstones stamped now, except:

- on the first scan after a launch, where they are dropped instead (see below);
- when more than 20 candidates and more than 25 % of the covered live entries
  disappear in one scan. That is a purge, eviction or clear-all, not a logout: the
  entries are dropped, nothing is tombstoned, and status reports it.

Logging out of a site removes a handful of cookies and propagates. Clearing the
whole store on one device does not clear the others.

## Lifecycle rules

| Event | Rule |
|---|---|
| **First open in a process** (`launch:true`) | Drop every session-cookie entry: the restart lost them. Number the remaining entries 1…N in the new replica. Start **warm-up**. |
| **Warm-up** | Scans are deferred and pulls are answered with `warming:true`; merges run. Warm-up ends after a complete pull from every peer seen in the first 15 s, or 30 s after launch. Peers' session cookies and newer versions therefore land before local state is stamped. |
| **First scan after launch** | Missing entries are dropped, not tombstoned. Cookies with no entry get the zero version, so an anonymous cookie a site set during warm-up cannot beat a peer's login. |
| **Sign-in later in the same process** (`launch:false`) | No warm-up. The first scan is normal, so a site logout made while signed out of Kelpie propagates. |
| **Account change** | Close the store and drop sessions; open it under the new subject (subject binding applies). |
| **Sign-out** | Drop sessions, stop listener and browsing, close the store. Website cookies stay, as today. |
| **iOS background** | Flush pending pushes in a background task, then stop listener and browsing. On foreground, restart both and treat it like a sign-in (`launch:false`). |
| **macOS renderer switch** | A rebase: refresh `observed` for every key from the new engine, stamp nothing and tombstone nothing. |

Every handshake, session, engine write and timer captures the account subject and
generation, and re-checks them before any effect and after every asynchronous
completion. Work from an old generation is discarded.

## Exchange protocol

Plaintext inside `/v1/sync/exchange`. The initiator keeps one long-poll pull open
and sends a push whenever it has local changes.

```json
// pull request: wait up to `wait` ms (max 25000) for changes after since.seq
{ "op": "pull", "since": { "replica": "<responder replica>", "seq": 120 }, "wait": 25000 }

// pull response
{ "replica": "<responder replica>", "head": 304, "seq": 180, "more": true,
  "incomplete": false, "warming": false, "records": [ … ],
  "yourWatermark": { "replica": "<initiator replica>", "seq": 75 } }

// push request
{ "op": "push", "replica": "<initiator replica>", "seq": 92, "more": false, "records": [ … ] }

// push response, sent after the responder commits
{ "yourWatermark": { "replica": "<initiator replica>", "seq": 92 } }
```

Record:

```json
{ "domain": ".example.com", "path": "/", "name": "sid",
  "hlc": [1731150000123, 0, "<replica>"], "deleted": false,
  "value": "…", "expires": 1733742000, "secure": true, "httpOnly": true, "sameSite": "Lax" }
```

Tombstones carry only `domain`, `path`, `name`, `hlc` and `deleted:true`.

- Each forwardable entry has a `localSeq` in its replica. A `since.replica` that
  is not the responder's current replica means `seq` 0, a full snapshot.
- Pages are ordered by `localSeq` and hold at most 500 records. `seq` is the
  `localSeq` of the last record included (or `head` when none remain); `more`
  says another page follows. The caller's next `since.seq` is `seq`.
- If a forwardable entry's value is not available (Android coverage gap), the page
  stops before it with `incomplete:true`; `seq` never passes an unsent record.
- The responder answers a pull at once if it has records after `since.seq`,
  otherwise when it gets one or when `wait` runs out.
- **Watermarks move only after commit.** The initiator sets its watermark for the
  responder to the response's `seq` after committing the page. The responder sets
  its watermark for the initiator to the push's `seq` after committing the push.
  `yourWatermark` tells the initiator where to start its next push.
- Watermarks live in memory and are keyed by replica, so a peer's restart always
  produces a full snapshot.

## core-sync C API

JSON strings in and out, freed with `kelpie_free_string`, like `state_c_api.h`.
All calls for one store run on one serial executor per platform; a merge
transaction holds it from plan to commit. A mutating call made while a merge is
open fails with `BUSY`.

```c
typedef struct KelpieSyncStore* KelpieSyncStoreRef;

// options: {"subject","replica","launch":bool,"nowMillis"}. NULL on I/O failure.
KelpieSyncStoreRef kelpie_sync_store_open(const char* path, const char* options_json);
void kelpie_sync_store_close(KelpieSyncStoreRef store);

// {"replica","head","entries","tombstones","localOnly","unapplied","skipped",
//  "warming","lastPurgeAt"} — counts only, never keys or values.
char* kelpie_sync_store_status(KelpieSyncStoreRef store);
void  kelpie_sync_store_finish_warmup(KelpieSyncStoreRef store);

// cookies: engine cookies in wire shape. coverage: {"all":true} | {"urls":[…]}.
// {"deferred":true} while warming, else {"changed":n,"head":s,"purge":bool}.
char* kelpie_sync_store_scan(KelpieSyncStoreRef store, const char* cookies_json,
                             const char* coverage_json, int64_t now_millis);

// Answers a pull (records after since, at most one page) from a fresh scan.
char* kelpie_sync_store_answer_pull(KelpieSyncStoreRef store, const char* pull_json,
                                    const char* cookies_json, const char* coverage_json,
                                    int64_t now_millis);
// Builds the next push for a peer from its watermark; {"push":null} when idle.
char* kelpie_sync_store_build_push(KelpieSyncStoreRef store, const char* watermark_json,
                                   const char* cookies_json, const char* coverage_json,
                                   int64_t now_millis);

// Merge transaction. source: {"replica","seq"} — the page's cursor, recorded as
// the watermark on commit. plan returns {"ops":[{"id","op":"set"|"delete","cookie"}]}.
// commit takes [{"id","ok","readback":[cookies with that name for the domain]}].
char* kelpie_sync_store_plan_merge(KelpieSyncStoreRef store, const char* records_json,
                                   const char* source_json, int64_t now_millis);
char* kelpie_sync_store_commit_merge(KelpieSyncStoreRef store, const char* results_json);
void  kelpie_sync_store_abort_merge(KelpieSyncStoreRef store);

char* kelpie_sync_store_watermark(KelpieSyncStoreRef store, const char* replica);

// Stateless helpers.
char* kelpie_sync_validate(const char* kind, const char* json);           // {"ok","error"}
char* kelpie_sync_transcript(const char* hello_pair_json);               // {"challenge"}
char* kelpie_sync_account_hints(const char* subject, int64_t now_millis); // {"current","accepted":[…]}
char* kelpie_sync_canonical_cookie(const char* cookie_json);             // {"syncable","key","cookie","reason"}
```

core-sync carries its own SHA-256 (checked against NIST vectors) because the
Apple and Android builds of `core/native` link no crypto library. ECDH, HKDF and
AES-GCM stay in platform code and must pass the shared vectors in
`core/native/core-sync/tests/vectors/handshake-v1.json`.

## Platform contract

| Piece | Contract |
|---|---|
| `CookieSource` | Default store only. `snapshot()` returns cookies plus honest coverage; `apply(op)` writes one cookie and `readback(domain, name)` returns every cookie with that name for the domain; a change signal. |
| `SyncCrypto` | P-256 key pair, ECDH, HKDF-SHA256, AES-256-GCM with AAD; passes the shared vectors. |
| `SyncAccount` | Live subject and generation, `issueTicket(challenge, clientId)` and `validateTicket(ticket, challenge, clientId)` over the existing UOA request path. |
| `SyncListener` | Sync-only HTTP listener on an ephemeral port with the address rule, body limits, deadlines and rate limits above, plus the `_kelpie-sync._tcp` advertisement. |
| `SyncBrowser` | mDNS browsing for `_kelpie-sync._tcp`, resolving address, port and TXT. |
| Sync service | Handshakes, sessions, the long-poll loop, pushes, warm-up, scheduling, generation fencing and status. Written once per language: Swift (Apple), Kotlin (Android), C++ (Windows and Linux). |

Logs never contain cookie names, domains, values, tickets, keys or boxes. Cookie
keys are browsing history.

### Scheduling

| Trigger | Action |
|---|---|
| Sign-in finished, or launch with a restored session | open store, advertise, browse |
| Peer found with an accepted hint and no session | handshake (initiator rule, backoff) |
| WebKit `WKHTTPCookieStoreObserver` (new), CEF/Android page load finished | scan after 1 s of quiet, then push to every session |
| Every 15 s on CEF; every 15 s for recently loaded hosts and every 5 min for all metadata URLs on Android | scan |
| Session expiry | handshake again while the peer still advertises |

### macOS

- The sync adapter is the only writer into the live default store while signed
  in. Retire the 2 s `SharedCookieJar` push/pull; a renderer switch copies cookies
  directly between the WebKit default store and the CEF global cookie manager and
  is a sync rebase. Keep `UOALoginCookies` behaviour.
- CEF access uses the global `CefCookieManager` through `CEFBridge`, not CDP.
- Add `_kelpie-sync._tcp` to `NSBonjourServices`; browse with `NWBrowser`.

### iOS

- Same Swift sync service as macOS, in `core/apple/shared/Sync`.
- `WKHTTPCookieStoreObserver` on the default store. Restart the listener and
  browser on foreground (today the listener is never restarted after suspension).
- Add `_kelpie-sync._tcp` to `NSBonjourServices`.

### Android

- Standalone only, so the default store is `CookieManager.getInstance()`.
- Bump androidx.webkit to a version with `CookieManagerCompat.getCookieInfo`.
  Before anything else, verify on a real WebView that the returned strings
  distinguish host-only from domain cookies and carry `SameSite`. If they do not,
  report it: sync on Android cannot be correct without it.
- Coverage URLs: `https://<host><path>` for every metadata entry, plus history
  hosts and hosts of recent page loads (unpartitioned tabs only).
- Second Ktor listener for sync; NSD browsing; HKDF from `HmacSHA256`.

### Windows and Linux

- A new C++ sync service in `core/native/desktop-sync`, shared by both, using
  cpp-httplib for the listener and client, core-sync for state, and a crypto shim
  (Windows CNG, Linux OpenSSL).
- `AccountService` gains subject, generation and the two ticket calls.
- The CEF adapter uses the global `CefCookieManager` on the UI thread.
- mDNS: Windows `DnsServiceRegister`/`DnsServiceBrowse`; Linux Avahi
  (`libavahi-client`). Without Avahi, Linux reports sync as unavailable.
- Windows may show a firewall prompt for the listener. If inbound is blocked, the
  Windows device still syncs by initiating to its peers.

## Agent access (API, CLI, MCP)

Existing authorization is unchanged.

| Method | Change |
|---|---|
| `get-cookies` | New `all:true` returns every cookie in the target store instead of the current page's; new `domain` filter; new `partition` target alongside `tabId`. Every platform returns real attributes (Android switches to `getCookieInfo`). |
| `set-cookies` (new) | Writes a list of cookies into the default store, a `partition` or a `tabId`; per-cookie results. |
| `copy-cookies` (new) | Copies from one store to another (default, partition or tab) with an optional `domain` filter; values never pass through the agent. |
| `get-cookie-sync-status` (new) | Signed-in state, support reason, this replica, live peers (platform, name, state, last sync, last error) and the store counts. |

MCP: `kelpie_get_cookies` gains `all`, `domain` and `partition`; new
`kelpie_set_cookies`, `kelpie_copy_cookies` and `kelpie_get_cookie_sync_status`.
CLI: `kelpie cookies list --all --domain --partition`, `kelpie cookies import`,
`kelpie cookies copy`, `kelpie cookies sync-status`.

Every device's default store holds the synced set, so an agent connected to any
one device sees cookies from all of them. **That also means any client paired
with any one device can read and plant cookies for all of them.** Writing into the
default store syncs like any other change. This is the feature the agents need; the
docs state it plainly.

## Security notes

- The sync listener serves only `hello`, `auth` and `exchange`. Automation keeps
  its own listener and authorization.
- Before UOA is called, a request costs one small JSON parse, one P-256 point
  check and a hint comparison, under the limits above.
- Plain LAN traffic carries public keys, nonces, transcript-bound tickets and
  AES-GCM boxes.
- A device signed in to the same account is trusted with every default-store
  cookie.
- Some sites bind sessions to a device, IP address or user agent and may reject a
  copied cookie. Kelpie syncs it; the site decides whether to honour it.

## Testing

- **core-sync (CTest):** canonicalisation and keys, SHA-256 vectors, HLC, merge
  commutativity and idempotence, three-device convergence through a relay, echo
  guard with an engine that normalises attributes, refused and reshaped writes,
  subject binding, first-sign-in adoption, launch warm-up and session-cookie
  restoration, purge guard, Android URL coverage, tombstone cap, pagination with
  concurrent changes, watermarks after commit, `BUSY` during a merge, message
  validation and limits.
- **Crypto vectors:** transcript, ECDH, HKDF and AES-GCM vectors checked by Swift,
  Kotlin, Windows CNG and OpenSSL.
- **Platform tests:** adapter round trips with real HttpOnly cookies, listener
  admission and limits, handshake with mocked UOA, generation fencing, iOS
  foreground restart, Android coverage.
- **Live journey:** two or more devices signed in to the same UOA account on the
  LAN. Sign in to a site on one and open it signed in on the others; sign out on
  one and see the others signed out; restart a device and see session cookies
  return; confirm an isolated tab stays signed out; copy cookies into an isolated
  tab through MCP; sign a second UOA account in on one device and confirm the
  first account's cookies do not reach it.

## Cross-Provider Review

Parallel adversarial review on 2026-11-09: a Claude reviewer and `codex exec`
read the first draft independently. Both found the handshake sound; both found
the replication rules unsafe. **[BOTH]** marks findings raised by both.

### Resolved

1. **[BOTH, CRITICAL] Cookies crossed accounts on a shared computer.** A
   per-subject metadata directory isolated metadata, not cookies. → The file is
   bound to one subject; existing cookies become `localOnly` under another
   subject.
2. **[BOTH, CRITICAL] Absence was treated as deletion.** Refused writes,
   evictions, ITP purges, partial reads and an empty store at launch would all
   broadcast logouts. → `unapplied` state, honest coverage, the purge guard, caps
   below engine limits and no tombstones on the first scan after launch.
3. **[BOTH, HIGH] Android host coverage was wrong.** A host-root query cannot see
   `Path=/account` or Secure-over-http cookies. → URL coverage with RFC 6265
   matching; failed queries abort the scan.
4. **[BOTH, HIGH] Tombstone GC resurrected deletions.** → Tombstones kept
   indefinitely, capped at 20 000.
5. **[BOTH, HIGH] The two-phase merge raced with scans and stale writes.** → The
   whole transaction holds the serial executor; mutating calls during it fail
   with `BUSY`. The false claim that commit protects local edits is gone.
6. **[BOTH, HIGH] macOS `SharedCookieJar` was an unaccounted second writer.** →
   Retired while sync owns the store; renderer switches are a rebase.
7. **[BOTH, HIGH] Pagination had no safe cursor.** → Entries are numbered 1…N at
   open; `seq` is the last record sent, distinct from `head`; `full` removed.
8. **[BOTH, MEDIUM] Stable device id tracked devices and broke under backup.** →
   Per-launch `replicaId`, never persisted; sync files excluded from backups.
9. **[BOTH, MEDIUM] Unauthenticated work was unbounded.** → Small bodies,
   deadlines, rate limits, eviction, single-use `/auth`, outgoing caps, backoff
   and bounded UOA concurrency.
10. **[Claude, CRITICAL] Read-backs under another key ping-ponged.** → Variants
    become `localOnly`; the remote record is `unapplied`.
11. **[Claude, CRITICAL] A restart could still log devices out.** → Session
    entries dropped at launch, warm-up before any stamping, zero version for the
    first scan after launch.
12. **[Claude, HIGH] The 24-hour skew allowance let a bad clock win.** → 2-minute
    gate at `hello`; the ignore rule is removed.
13. **[Claude, HIGH] The responder had no way to notify.** → `notify` and the
    60 s timer replaced by a long-poll pull.
14. **[Claude, MEDIUM] Watermarks advanced before commit.** → They move only on
    commit.
15. **[Claude, MEDIUM] Strict `seq` killed sessions on ordinary failures.** →
    64-entry replay window.
16. **[Claude, MEDIUM] New export/import methods duplicated existing ones.** →
    `get-cookies` gains `all`; only `set-cookies`, `copy-cookies` and status are
    new.
17. **[Codex, HIGH] Either side could send requests, reusing GCM nonces.** → The
    initiator is the only requester; directions use separate keys.
18. **[Codex, HIGH] `/auth` was replayable.** → The first `/auth` consumes the
    handshake; keys are installed once.
19. **[Codex, HIGH] Asynchronous work was not fenced by account generation.** →
    Every operation captures and re-checks subject and generation.
20. **[Codex, HIGH] One version could carry different values.** → Entries keep
    the accepted attributes and value hash; forwarding sends the accepted record.
21. **[Codex, HIGH] Failed writes became fresh local changes.** → `observed` keeps
    the engine's real state; only a genuine engine change is a local edit.
22. **[Codex, HIGH] Ordinary sign-in was treated as a restart.** → Restart rules
    apply only to the first open in a process.
23. **[Codex, HIGH] Unknown attributes were exported as defaults.** →
    `"Unspecified"` is explicit; adapters skip cookies they cannot describe.
24. **[Codex, HIGH] The `|`-joined key was ambiguous.** → JSON-array key.
25. **[Codex, MEDIUM] Private addresses do not prove LAN locality.** → Eligible
    physical interfaces and directly connected subnets, both directions.
26. **[Codex, MEDIUM] Browsing ignored the midnight hint tolerance.** → Both sides
    use the accepted set; adverts refresh at the date change.
27. **[Claude, LOW] Platform gaps.** → iOS listener restart, `NSBonjourServices`,
    Android cleartext to peers, Avahi, the Windows firewall fallback and log
    hygiene are in the platform sections.

### Not adopted

- **[Claude] Restrict default-store export and import to account-paired
  clients.** The person asked for every MCP agent to be able to pull any cookie
  out and save it elsewhere. Existing pairing already grants full browser control,
  including `get-cookies` on the default store. The broader reach is documented
  instead.
- **[Codex] Refuse sync under a different subject until the store is cleared.**
  That needs new UI and blocks the new account entirely. `localOnly` keeps the
  previous account's cookies local without blocking sync of new ones.
