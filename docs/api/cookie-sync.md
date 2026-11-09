# Cookie sync protocol (v1)

Kelpie devices signed in to the same UOA account on the same local network keep
one shared set of default-store cookies. They talk directly to each other. No
server stores or sees a cookie; UOA only proves that both devices belong to the
same account.

This page is the wire contract every platform implements. The design record,
with the reasoning and the review that shaped it, is
[the cookie sync plan](../plans/2026-11-09-p2p-cookie-sync.md). The agent-facing
methods (`get-cookies all:true`, `set-cookies`, `copy-cookies`,
`get-cookie-sync-status`) are in [cookies.md](cookies.md).

## Contents

- [Scope](#scope)
- [Discovery](#discovery)
- [HTTP rules and limits](#http-rules-and-limits)
- [Handshake](#handshake)
- [Encrypted channel](#encrypted-channel)
- [Exchange messages](#exchange-messages)
- [Cookie records](#cookie-records)
- [Error codes](#error-codes)
- [Conformance](#conformance)

## Scope

- **Default store only.** Partitioned tabs never sync, never receive synced
  cookies and never contribute to the sync.
- **Standalone apps only.** An embedded browser inside another app does not run
  the sync service.
- **Signed in only.** Sync starts on sign-in and stops on sign-out or account
  change. There is no toggle.
- **Same network only.** No relay, rendezvous server or TURN. A device that was
  away catches up the next time it shares a network with another signed-in
  Kelpie.

All merge, change-feed, validation and transcript logic lives in core-sync
(`core/native/core-sync`, header `include/kelpie/sync_c_api.h`). Platforms supply
the cookie adapter, crypto, UOA calls, listener, mDNS and the sync service that
drives them. A platform must call core-sync rather than reimplement it.

## Discovery

### Service

| Item | Value |
|---|---|
| mDNS service type | `_kelpie-sync._tcp` (separate from the automation service `_kelpie._tcp`) |
| Port | Ephemeral, chosen at bind time |
| TXT `v` | `1` |
| TXT `id` | This device's `replicaId` |
| TXT `h` | This device's current `accountHint` |

iOS and macOS list `_kelpie-sync._tcp` in `NSBonjourServices`. Advertising and
browsing run only while signed in; sign-out, account change and iOS
backgrounding stop both. Linux needs Avahi; without it the device reports
`mdns-unavailable`.

### Replica id

`replicaId` is 16 random bytes, base64url without padding (22 characters). It is
new on every launch and every sign-in and is never written to disk. It names one
run of one store, so a backup or restore cannot clone it and it cannot track a
device across launches.

### Account hint

```
accountHint = base64url(first 8 bytes of
              SHA-256("kelpie-sync-hint-v1" || 0x00 || subject || 0x00 || date))
```

`subject` is the UOA subject. `date` is the UTC date as `YYYY-MM-DD`. The hint is
11 characters. A device accepts the hints for yesterday, today and tomorrow (UTC)
and refreshes its advertisement when the UTC date changes.
`kelpie_sync_account_hints(subject, now)` returns `{"current","accepted":[…]}`.

The hint only saves UOA calls when many Kelpie users share a network. It is
public and authorises nothing.

### Address rule

The listener accepts a connection only when the peer address is loopback,
IPv4 or IPv6 link-local, or inside the directly connected subnet of an eligible
interface. Eligible interfaces are physical Wi-Fi and Ethernet. VPN, tunnel,
point-to-point and cellular interfaces are not. Outgoing connections apply the
same rule to resolved addresses and prefer IPv4 and link-local.

### Who connects

There is one session per pair of devices, and only the **initiator** sends
requests.

1. The device with the lexicographically smaller `replicaId` initiates.
2. The other device initiates only if no session has formed 15 s after it first
   saw the peer. That covers a listener blocked by a firewall.
3. A peer whose TXT `h` is not in the accepted set is ignored.

## HTTP rules and limits

The sync listener serves only `POST /v1/sync/hello`, `POST /v1/sync/auth` and
`POST /v1/sync/exchange`. It is separate from the automation listener and never
accepts automation tokens. Windows and Linux keep automation on loopback; the
sync listener is the only LAN listener there.

- Requests are `POST` with `Content-Type: application/json`.
- A request with an `Origin` header, a `Transfer-Encoding` header or more than
  one `Content-Length` is rejected.
- Every response carries `Cache-Control: no-store`.

| Limit | Value |
|---|---|
| `hello` and `auth` body | 16 KiB; body read deadline 5 s |
| `exchange` body | 4 MiB; accepted only with a live `X-Kelpie-Sync-Session` header, checked before the body is read |
| `hello` rate | 10 per minute per source address, 60 per minute in total |
| Pending handshakes | 8; a new one evicts the oldest |
| Pending handshake lifetime | 60 s |
| Outgoing handshakes | 10 per minute in total |
| Backoff after a failed attempt | Per peer, exponential from 5 s to 5 min |
| Concurrent UOA calls | 2 |
| Session lifetime | 10 minutes |

## Handshake

Binary values are base64url without padding. Times are Unix milliseconds.
`kelpie_sync_validate(kind, json)` checks every message below; its `kind` is
given in each heading.

### 1. Hello (`hello`, `hello-reply`)

The initiator generates an ephemeral P-256 key pair and a nonce, then sends:

```json
POST /v1/sync/hello
{ "v": 1, "replica": "DrlGeFx11w1azJdmwzXszw", "hint": "…", "now": 1731150000000,
  "platform": "macos", "name": "Studio Mac",
  "key": "<P-256 public key, x9.63 uncompressed>", "nonce": "<32 bytes>" }
```

| Field | Rule |
|---|---|
| `v` | `1` |
| `replica` | 16 bytes |
| `hint` | 8 bytes; must be in the responder's accepted set |
| `now` | Integer; within 2 minutes of the responder's clock |
| `platform` | 1–32 characters from `a-z`, `0-9`, `-` (`macos`, `ios`, `android`, `windows`, `linux`) |
| `name` | 0–64 bytes of UTF-8 with no control characters |
| `key` | 65 bytes: `0x04` followed by X and Y. The platform's crypto library also checks that the point is on the curve |
| `nonce` | 32 bytes |

The responder refuses, before any UOA call:

- an unknown `v`, a malformed field or an invalid key (`400`);
- a hint outside its accepted set: `409 {"error":"ACCOUNT_MISMATCH"}`;
- a clock difference over 2 minutes: `409 {"error":"CLOCK_SKEW"}`. Both sides
  show this peer as `clock-skew` in status.

Otherwise it keeps a pending handshake in memory for 60 s and replies with its
own ephemeral key and nonce:

```json
200
{ "v": 1, "replica": "OjJiVoGP30gQg8yzYiW6bQ", "now": 1731150000050,
  "platform": "ios", "name": "Kitchen iPad",
  "key": "<P-256 public key>", "nonce": "<32 bytes>",
  "handshakeId": "<32 bytes>", "expiresAt": 1731150060050 }
```

The reply follows the same field rules, without `hint`, plus `handshakeId`
(32 bytes) and `expiresAt` (integer). The initiator applies the same 2-minute
clock check to the reply.

### 2. Transcript

Both sides compute:

```
T = SHA-256("kelpie-sync-v1"
            || 0x00 || initiator.replica || 0x00 || initiator.key || 0x00 || initiator.nonce
            || 0x00 || responder.replica || 0x00 || responder.key || 0x00 || responder.nonce)
challenge = base64url(T)        // 43 characters, UOA's challenge format
```

The six values are hashed as their base64url **text** exactly as sent, not as
decoded bytes. Every platform computes it with
`kelpie_sync_transcript({"initiator":{replica,key,nonce},"responder":{…}})`,
which returns `{"challenge"}`.

### 3. Mutual UOA proof

Each side asks UOA for a ticket over the same challenge with a role-specific
client id, using its own UOA session (scope `kelpie.connect`). The UOA endpoints
are the ones [account pairing](account-pairing.md) uses.

| Side | Issue (`POST /oauth/kelpie/pair`) | Validated by the peer with (`POST /oauth/kelpie/pair/validate`) |
|---|---|---|
| Initiator | `{challenge, clientId:"kelpie-sync:i:<initiator replica>"}` | `{ticket, challenge, clientId:"kelpie-sync:i:<initiator replica>"}` |
| Responder | `{challenge, clientId:"kelpie-sync:r:<responder replica>"}` | `{ticket, challenge, clientId:"kelpie-sync:r:<responder replica>"}` |

Only a validation answer of `{active:true}` continues. The role prefixes stop a
ticket being reflected back to the device that issued it. A swapped key produces
a different transcript, so a ticket UOA issued for one fails against the other.
Neither device ever receives a spendable UOA credential.

UOA downtime blocks new sessions. Sync never falls back to an unauthenticated
mode.

### 4. Auth (`auth`, `auth-reply`)

```json
POST /v1/sync/auth
{ "handshakeId": "<32 bytes>", "ticket": "<initiator ticket, 1–8192 printable bytes>" }
```

The first `/auth` for a `handshakeId` **consumes** the pending handshake,
whatever the outcome. A second one gets `401 {"error":"SYNC_SESSION"}`.

The responder validates the initiator's ticket with its own UOA session. On
`{active:true}` it installs the session keys, exactly once, and replies:

```json
200
{ "ticket": "<responder ticket>", "sessionExpiresAt": 1731150600000 }
```

The initiator validates that ticket the same way, with the responder's client
id, and installs its keys. Either failure ends the attempt. A retry starts again
from `hello` with new keys and nonces.

### 5. Session keys

```
Z   = ECDH(own ephemeral private key, peer ephemeral public key)     // 32 bytes
i2r = HKDF-SHA256(ikm = Z, salt = T, info = "kelpie-sync-v1 i2r", length = 32)
r2i = HKDF-SHA256(ikm = Z, salt = T, info = "kelpie-sync-v1 r2i", length = 32)
```

`T` is the 32-byte transcript hash, not its base64url text. Ephemeral private
keys are discarded after derivation.

A session lasts until `sessionExpiresAt` (10 minutes), sign-out, account change,
iOS backgrounding or either side's restart. A new session needs a new handshake
and fresh UOA proofs, so revoking a UOA session cuts sync off within 10 minutes.

## Encrypted channel

```json
POST /v1/sync/exchange
X-Kelpie-Sync-Session: <handshakeId>
{ "seq": 7, "box": "<ciphertext || 16-byte tag>" }
```

| Item | Rule |
|---|---|
| Direction keys | Requests are sealed with `i2r`, responses with `r2i` (AES-256-GCM) |
| Nonce | 12 bytes: 4 zero bytes, then the request `seq` as a 64-bit big-endian integer. A response uses its request's `seq` |
| AAD | UTF-8 text `kelpie-sync-v1\0<sessionId>\0<req or res>\0<seq in decimal>`; `sessionId` is the `handshakeId` text |
| `box` | Ciphertext followed by the 16-byte tag, base64url; at least 16 bytes decoded |
| `seq` | Unsigned integer, starting at 1 |

The response body is `{ "seq": <request seq>, "box": "…" }` with the same rules.

- Only the initiator sends requests. Separate direction keys and per-request
  nonces mean a nonce never repeats under one key.
- The initiator may have a pull and a push in flight at once.
- The responder keeps a 64-entry replay window. It accepts a `seq` it has not
  seen that is no more than 64 below the highest seen, and rejects any other.
- A box that fails to open, or a `seq` outside the window, is rejected without a
  sealed response.
- An unknown or expired session returns `401 {"error":"SYNC_SESSION"}`. The
  initiator then handshakes again.
- Responses are never cached or replayed.

**Vectors.** `core/native/core-sync/tests/vectors/handshake-v1.json` fixes every
byte: both key pairs, the transcript, the shared secret, `i2r`, `r2i`, nonces,
AAD and sealed boxes. Every platform's crypto must reproduce it.
`packages/shared/tests/cookie-sync-vectors.test.ts` re-derives it with Node's
crypto, so a hand-edited vector file fails the build.

## Exchange messages

The plaintext inside a box is one of the messages below. The initiator keeps one
long-poll pull open and sends a push whenever it has local changes.

### Pull

```json
// request: wait up to `wait` ms (at most 25000) for changes after since.seq
{ "op": "pull", "replica": "<initiator replica>",
  "since": { "replica": "<responder replica>", "seq": 120 }, "wait": 25000 }

// response
{ "replica": "<responder replica>", "head": 304, "seq": 180, "more": true,
  "incomplete": false, "warming": false, "records": [ … ],
  "yourWatermark": { "replica": "<initiator replica>", "seq": 75 } }
```

- The responder answers at once if it has records after `since.seq`, otherwise
  when it gets one or when `wait` runs out.
- A `since.replica` that is not the responder's current replica means `seq` 0:
  a full snapshot.
- A page holds at most 500 records, ordered by the responder's local sequence.
  `seq` is the sequence of the last record included, or `head` when none remain.
  `more` says another page follows. The next `since.seq` is `seq`.
- `incomplete: true` means the page stopped before a record whose value the
  responder cannot read yet (an Android coverage gap). `seq` never passes an
  unsent record.
- `warming: true` means the responder is in launch warm-up (at most 30 s) and is
  still collecting its peers' cookies. The page is empty; ask again.
- `yourWatermark` is how far the responder has committed the initiator's pushes.

### Push

```json
// request
{ "op": "push", "replica": "<initiator replica>", "seq": 92, "more": false, "records": [ … ] }

// response, sent only after the responder has committed the push
{ "yourWatermark": { "replica": "<initiator replica>", "seq": 92 } }
```

The initiator builds a push from the last `yourWatermark` it received
(`kelpie_sync_store_build_push`). A `null` push means nothing to send.

### Watermarks

- Watermarks move only after commit. The initiator sets its watermark for the
  responder to a pull response's `seq` after committing that page. The responder
  sets its watermark for the initiator to a push's `seq` after committing it.
- Watermarks live in memory and are keyed by replica, so a peer's restart always
  produces a full snapshot.

### Applying records

`plan_merge` turns records into engine operations, the adapter writes each one and
reads it back, and `commit_merge` records the outcome. The whole transaction holds
the store's serial executor; a mutating call during it fails with `BUSY`. The
read-back returns every cookie in the engine with the op's `name` whose domain,
with or without a leading dot, equals the op's domain without its dot. A missing
or failed read-back is reported as `ok:false` with whatever the engine still holds,
never as an empty result.

## Cookie records

```json
{ "domain": ".example.com", "path": "/", "name": "sid",
  "hlc": [1731150000123, 0, "<replica>"], "deleted": false,
  "value": "…", "expires": 1733742000, "secure": true, "httpOnly": true, "sameSite": "Lax" }
```

A tombstone carries only `domain`, `path`, `name`, `hlc` and `deleted: true`.

| Field | Rule |
|---|---|
| Identity | The JSON array `["<domain>","<path>","<name>"]` |
| `domain` | Lower-case. A domain cookie starts with `.`; a host-only cookie does not |
| `path` | As stored; `/` when absent |
| `name`, `value` | Exact bytes; name plus value at most 4 KiB |
| `expires` | Whole Unix seconds, or `null` for a session cookie |
| `secure`, `httpOnly` | Booleans |
| `sameSite` | `Strict`, `Lax`, `None` or `Unspecified` (no attribute). An adapter that cannot tell skips the cookie; unknown never becomes a default |
| `hlc` | `[wall ms, counter, replica]`, compared in that order; `replica` at most 64 characters |

Never synced: cookies for loopback hosts (`localhost`, `*.localhost`,
`127.0.0.0/8`, `::1`), cookies the engine marks as partitioned (CHIPS), and
anything in a partitioned tab's store. `kelpie_sync_canonical_cookie` reports
`malformed`, `too_large`, `loopback_host` or `partitioned` for a cookie it
refuses.

**Caps.** A remote set that would give one domain more than 150 cookies, or the
store more than 3 000, is ignored and counted as `skipped` in status. That keeps
the synced set below the smallest engine's limits (Chromium: 180 per domain,
about 3 300 in total). Tombstones are kept indefinitely, up to 20 000; beyond
that the oldest by version are dropped.

**Merge.** A remote record wins over no entry, over a `localOnly` entry and over
an older version; an equal or newer local version wins. The merge is commutative
and idempotent, so changes forwarded through a third device converge. Scans,
the purge guard, launch warm-up and account binding are specified in the
[plan's data model and lifecycle rules](../plans/2026-11-09-p2p-cookie-sync.md#data-model).

## Error codes

These are the only error bodies a peer acts on.

| Status | Body | Sent by | The initiator |
|---|---|---|---|
| 409 | `{"error":"ACCOUNT_MISMATCH"}` | `hello` | Counts a failed attempt, with backoff |
| 409 | `{"error":"CLOCK_SKEW"}` | `hello` | Shows the peer as `clock-skew` and counts a failed attempt |
| 401 | `{"error":"SYNC_SESSION"}` | `auth`, `exchange` | Starts again from `hello` |

Every other rejection uses the matching HTTP status (`400` malformed, `404`
unknown path, `405` not `POST`, `408` read deadline, `413` body too large, `429`
rate limit) and counts as a failed attempt, with backoff.

core-sync's C API reports its own failures as `{"error":"<CODE>","message":"…"}`.
The codes are `INVALID_JSON`, `INVALID_MESSAGE`, `INVALID_OPTIONS`,
`INVALID_COOKIES`, `INVALID_COVERAGE`, `INVALID_RESULTS`, `INCOMPLETE_RESULTS`,
`NO_STORE`, `NO_MERGE`, `BUSY` and `INTERNAL`. They never go on the wire.

## Conformance

A platform conforms when it:

- passes the shared vectors for ECDH, HKDF-SHA256 and AES-256-GCM with AAD;
- uses `kelpie_sync_transcript`, `kelpie_sync_account_hints` and
  `kelpie_sync_validate` instead of its own versions;
- enforces the address rule, limits, single-use `/auth` and replay window above;
- captures the account subject and generation for every handshake, session,
  engine write and timer, and discards work from an old generation;
- logs no cookie names, domains, values, tickets, keys or boxes. Cookie keys are
  browsing history.
