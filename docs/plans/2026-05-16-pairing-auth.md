# Pairing & Authentication for `/v1/*` HTTP API

**Status:** Design — pending cross-provider review.
**Driver:** Round-2 review finding (CRITICAL #1). Any LAN peer can call `/v1/evaluate` and run arbitrary JS in any tab. No pairing, no auth, wildcard CORS. Same exposure on iOS, Android, macOS.

## Goals

1. Block unauthenticated `/v1/*` calls. First contact requires explicit on-device approval.
2. Three responses from the device user: **Yes (this session)**, **No (deny)**, **Always (persist)**.
3. Tokens are bearer tokens — opaque, per-client, revocable.
4. CLI handles pairing transparently. End-user runs one `kelpie pair` (or it auto-prompts) and forgets about it.
5. No regression for `kelpie discover` (mDNS browsing stays anonymous).
6. Storage obeys `No Keychain` rule on macOS: encrypted file under app support, not Keychain.

## Non-goals

- Token rotation / expiry (deferred; tokens are long-lived until revoked).
- Multi-user device accounts.
- Transport encryption (TLS on local LAN is a separate workstream).
- Replacing CORS — we just tighten it (no `*`, only `null` + same-origin).

## Protocol

### Endpoints

The auth middleware **denies by default**. The unauth allowlist is an **exact-match** decoded-path set:

```
/v1/pair
/v1/pair/status
/v1/get-device-info
```

Everything else — including `/mcp`, `/sse`, and every other `/v1/*` method — requires `Authorization: Bearer <token>`.

| Method | Auth | Body | Response |
|---|---|---|---|
| `POST /v1/pair` | none + CSRF gate | `{clientId: uuid, clientName: string}` | `202 {status: "pending", requestId: nonce, expiresAt: ms, sourceAddress: ip}` |
| `GET /v1/pair/status?requestId=X` | none | — | `200 {status: "pending"\|"approved"\|"denied"\|"expired"\|"not_found", scope?: "session"\|"persistent", token?: string}` — token returned **once** then pending entry deleted |
| `DELETE /v1/pair` | bearer (revokes self only — clientId derived from token) | — | `200 {success: true}` |
| `GET /v1/get-device-info` | none | — | `200 {name, platform, version, requiresPairing: true}` |
| `/mcp`, `/sse`, all other `/v1/*` | **bearer required** | unchanged | `401 {error: {code: "UNAUTHORIZED"}}` |

### Token lifecycle

- Token is **32 bytes from CSPRNG** (`SecRandomCopyBytes` / `SecureRandom` / `crypto.randomBytes`), base64url-encoded.
- The token plaintext is returned **exactly once** on the originating client's `GET /v1/pair/status` call, then the pending entry is deleted and a separate persistent (`Always`) or in-memory (`Yes`) record is written with **only the SHA-256 hash of the token**.
- Server-side comparison is constant-time SHA-256 over the incoming bearer.
- Theft of `pairings.json` = theft of hashes, not usable tokens.

### Pairing request binding

The server records, when `POST /v1/pair` arrives:
```
requestId  (32B CSPRNG)
clientId   (from body, treated as untrusted display string)
clientName (truncated to 64 chars, control chars stripped, labeled self-reported)
sourceAddress (from socket; immutable for this request)
createdAt
```

The UI prompt displays `clientName + sourceAddress`. The approve / deny / always action carries the `requestId`. If the stored `sourceAddress` for that `requestId` differs from the socket peer at status-poll time (or `requestId` doesn't exist), the call returns `not_found`.

### CSRF gate on `POST /v1/pair`

Pairing endpoints are reachable by malicious web pages on the LAN unless we lock them. Required for `POST /v1/pair` to proceed:

- `Content-Type: application/json` (rejected if absent or different).
- `Origin` header **absent** OR present and matching a small allowlist (`null` is **not** allowed). CLI fetch does not send `Origin`; this is the natural discriminator.
- Single `Authorization` and `Content-Length` headers; `Transfer-Encoding` rejected.

### Headers

Client must send on every authenticated request:
```
Authorization: Bearer <token>
```

Server **strips** the `Authorization` header (and any `token`/bearer-shaped values) from all logs.

Server **rejects** duplicate `Authorization`, duplicate `Content-Length`, and any `Transfer-Encoding` header before routing.

`clientId` is a stable UUID per CLI install. `clientName` is `username@hostname`, displayed as self-reported.

### CORS

Removed entirely. CLI fetch is not a browser and doesn't need it. No `Access-Control-Allow-Origin` header is sent. (Earlier draft echoing `null` was exploitable from sandboxed iframes.)

### Network binding

Native HTTP server binds only to non-routable interfaces: loopback + link-local + RFC1918. VPN tunnels and public IPv6 interfaces are excluded by default. Each accepted bind address is logged at startup for operator visibility.

CLI's HTTP MCP server (`kelpie mcp --http`) binds to `127.0.0.1` by default. `--bind 0.0.0.0` requires an additional `--unsafe-host` flag and emits a loud warning, because that mode forwards stored bearer tokens.

### Prompt coalescing

One visible pending prompt **per source address**. A new `POST /v1/pair` from the same source replaces the existing pending entry (idempotent for retries). A `POST` from a different source queues; only one prompt visible at a time. UUID rotation from a single attacker cannot spam the UI.

### Cache control

`/v1/pair` and `/v1/pair/status` responses include `Cache-Control: no-store, no-cache` and `Pragma: no-cache`.

### Approval state machine

```
        POST /v1/pair
        ────────────►   ┌──────────┐
                        │ PENDING  │  (UI prompt visible)
                        └────┬─────┘
              user taps      │
        ┌────────┬───────────┴───────────┬────────────┐
        │ Yes    │ Always                │ No         │
        ▼        ▼                       ▼            ▼
   ┌────────┐ ┌─────────────┐       ┌────────┐   timeout 5min
   │APPROVED│ │APPROVED +   │       │ DENIED │   ┌────────┐
   │ (mem)  │ │PERSISTED    │       │        │   │EXPIRED │
   └────────┘ └─────────────┘       └────────┘   └────────┘
```

- **Yes** — token kept in-memory; cleared on app restart.
- **Always** — token written to encrypted storage; survives restart.
- **No** — `clientId → denied` recorded; future `POST /v1/pair` for that clientId returns `403` immediately (no prompt spam).
- **Expired** — pending state TTL 5 min; user must re-`POST /v1/pair`.

### CORS

- Replace wildcard `Access-Control-Allow-Origin: *` with explicit echo of `Origin: null` (CLI fetch) and same-origin only.
- Preflight `OPTIONS` allowed for `Authorization` and `Content-Type` headers.

## Server-side data

Persistent store, **token hashes only**:

```jsonc
// iOS:     <AppSupport>/Kelpie/pairings.json (NSFileProtectionComplete, atomic write)
// Android: EncryptedSharedPreferences "kelpie-pairings"
// macOS:   <AppSupport>/Kelpie/pairings.json (POSIX 0600, atomic write — no fake AES on top)
{
  "version": 1,
  "pairings": [
    {
      "clientId": "uuid",
      "clientName": "alice@thinkpad",
      "tokenHashSha256": "hex",
      "approvedAt": 1716000000000,
      "lastSeenAt": 1716001000000
    }
  ]
}
```

**Atomic write** on every platform: write to `pairings.json.tmp`, `fsync`, `rename`. Crash mid-write does not corrupt the store.

**Denied list is in-memory only.** "No" suppresses re-prompts from that source address for 10 minutes, then expires. This blocks UUID rotation spam from a single source without creating a permanent DoS via clientId spoofing.

**In-memory only:** pending pair requests (`requestId`, clientId, clientName, sourceAddress, createdAt) + session-only approvals (clientId, tokenHash, expiresOnRestart=true).

**Token comparison:** the server hashes the incoming bearer with SHA-256, then compares to stored hash with `memcmp` over fixed-length 32-byte digest (constant time since lengths match).

**Why hashes, not plaintext-on-disk:** macOS AES-GCM with a UserDefaults-derived key is fake protection — any same-user process can derive the same key. Switching to hashed tokens means even local read of `pairings.json` doesn't grant API access.

## UI

### Mobile (iOS + Android — parity)

Modal sheet. **Default button is `No`** (Cancel-equivalent — Return key triggers it). "Always allow" is visually distinct and placed last; not the default.

```
┌─────────────────────────────────────┐
│  Allow this client to control       │
│  this browser?                      │
│                                     │
│  Name (self-reported):              │
│   "alice@thinkpad"                  │
│                                     │
│  From: 192.168.1.42                 │
│                                     │
│  This client will be able to        │
│  navigate, type, screenshot, run    │
│  JavaScript, and read cookies.      │
│                                     │
│  [    No    ] ← default             │
│  [ Yes, once ]                      │
│  [ Always allow ]                   │
└─────────────────────────────────────┘
```

`clientName` is shown labeled **self-reported**; source IP is taken from the socket and is authoritative.

Settings:
- **Paired clients** (persistent) — list with timestamps + revoke. Revoke deletes the entry entirely (next attempt re-prompts).
- **Active sessions** (in-memory) — list of `Yes, once` approvals with revoke button. Cleared on app restart.
- **Recently denied** (in-memory, expires) — informational list of source addresses currently suppressed.

### macOS

Same dialog as an `NSAlert` with three buttons (default `No`, then `Yes once`, then `Always`). Settings panel → "Paired clients" tab with the three sections above. Buttons use the existing AppKit-backed pattern (per AGENTS.md SwiftUI+WebView rule).

## CLI

### `kelpie pair <device>` (new command)

Explicit flow for scripts:
1. `POST /v1/pair` with `{clientId, clientName}`. Receive `{requestId, expiresAt, sourceAddress}`.
2. Poll `GET /v1/pair/status?requestId=X` every 1s for up to 5 min.
3. On `approved` → response includes `scope: "session"|"persistent"` and `token`.
   - `persistent` → save `{deviceFingerprint → token}` to `~/.kelpie/tokens.json` (mode 0600).
   - `session` → keep in **process memory only**; do NOT write to disk.
4. On `denied` / `expired` / `not_found` → exit 2 with message.

### `deviceFingerprint` (anti-mDNS-spoof)

Tokens are pinned not by `deviceId` alone (spoofable in mDNS TXT records) but by `deviceId + lastKnownHost + lastKnownPort`. When a `deviceId` re-appears at a different `(host, port)`, the CLI refuses to send the stored token and forces re-pair with a warning:
```
Device "MyPhone" was at 192.168.1.42:8420 but now claims 192.168.1.99:8420.
This could be a network change or an mDNS spoofing attempt.
Re-pair? [y/N]
```

### Implicit pairing in normal commands

When any command hits `401 UNAUTHORIZED`, the CLI auto-runs the pair flow against that device with a prompt:
```
Device "MyPhone" requires pairing. Approve on device when prompted. [Y/n]
```
On approve, retries the original command transparently. **Session-scope approvals are not persisted across CLI invocations** — the user re-approves next session.

### Token store

`~/.kelpie/` directory: created with `0700`, refuses to operate if a symlink, refuses to operate if existing perms are world/group readable (will chmod on first run if owned by current user).

`~/.kelpie/tokens.json` (mode 0600, atomic write):
```json
{
  "clientId": "uuid",
  "version": 1,
  "tokens": {
    "<deviceId>:<host>:<port>": "bearer-token"
  }
}
```

### MCP server

`kelpie mcp` (stdio) — loads persistent tokens from `~/.kelpie/tokens.json` at startup. Same auto-pair on 401, surfaces `pairing_required` to the LLM rather than blocking the loop.

`kelpie mcp --http` — binds to `127.0.0.1` by default. `--bind 0.0.0.0` requires `--unsafe-host` and prints a warning that stored tokens will be drivable by anyone reaching the MCP port.

### Log redaction

CLI and MCP responses strip:
- `Authorization` header values
- response body fields named `token` or `bearer`
- any string matching the bearer-shape regex `[A-Za-z0-9_-]{40,}` from error messages

before they reach stderr / MCP tool output / logs.

## Migration

- Existing deployments have no tokens. First request from any CLI returns `401`.
- CLI's implicit pairing flow handles this transparently (one user tap per device).
- No back-compat unauthenticated mode — clean break (matches `Simplification First`).

## Code touchpoints

| Area | Files |
|---|---|
| iOS server | `Network/HTTPServer.swift`, new `Network/PairingStore.swift`, new `Network/AuthMiddleware.swift`, `Network/Router.swift` |
| iOS UI | new `Views/PairingDialog.swift`, `Views/SettingsView.swift` (paired-clients section), `KelpieApp.swift` (modal hook) |
| Android server | `network/HTTPServer.kt`, new `network/PairingStore.kt`, new `network/AuthMiddleware.kt` |
| Android UI | new `ui/PairingDialogFragment.kt`, settings screen update |
| macOS server | `Network/HTTPServer.swift`, new `Network/PairingStore.swift`, new `Network/AuthMiddleware.swift` |
| macOS UI | new `Views/PairingAlert.swift`, settings panel paired-clients view |
| CLI | new `src/auth/pairing.ts`, new `src/auth/token-store.ts`, `src/client/http-client.ts` (auth header + 401 retry), `src/commands/pair.ts`, `src/discovery/scanner.ts` (no auth needed) |
| Shared | `src/api-types.ts` add `PairRequest`/`PairStatus`; `src/mcp-tools.ts` add `kelpie_pair` |
| Docs | `docs/api/`, `docs/cli.md`, `docs/functionality.md`, `docs/architecture.md` |

## Test plan

- Unit: token comparison constant-time, denied list short-circuit, expired pending eviction.
- Integration: CLI auto-pair on 401, persistent vs session approval surviving app restart.
- Manual: dialog appearance on each platform, revoke flow, "No" suppresses re-prompt.

## Out of scope decisions (deliberate)

- **Why bearer over HMAC**: simpler, same effective security on LAN, easier CLI implementation.
- **Why 5 min pending TTL**: long enough for user to find phone, short enough that an old pending request can't be silently approved later.
- **Why no per-action permissions**: `/v1/evaluate` already grants full power; finer-grained controls are theater.

## Cross-Provider Review

Codex performed an adversarial review of the original draft (`codex exec`, 2026-05-16). 27 findings were raised. Each is resolved below; the resolution is reflected in the body of this doc.

### CRITICAL

1. **`/mcp` is a full bypass** — auth was scoped to `/v1/*`. **Resolved**: auth middleware now denies by default; unauth allowlist is an exact-match list (`/v1/pair`, `/v1/pair/status`, `/v1/get-device-info`). `/mcp` and `/sse` require bearer.
2. **CLI HTTP MCP exposes stored tokens to LAN** — `kelpie mcp --http` could bind 0.0.0.0. **Resolved**: defaults to `127.0.0.1`; `--bind 0.0.0.0` requires `--unsafe-host` + warning.
3. **mDNS spoofing token theft** — CLI keyed tokens by `deviceId` alone. **Resolved**: token store keyed by `deviceId:host:port`; re-pair forced when fingerprint changes.
4. **`Origin: null` CORS** — sandboxed iframes can match. **Resolved**: CORS removed entirely. CLI fetch doesn't need it.

### HIGH

5. **`pair/status` leaked token via clientId enumeration** — anyone observing `clientId` could poll. **Resolved**: status poll keyed by server-issued `requestId` nonce (32B CSPRNG); token returned once then pending entry deleted.
6. **Approval not bound to immutable request** — concurrent prompts could approve the wrong one. **Resolved**: approval action carries `requestId`; server rejects if `(requestId, clientId, sourceAddress)` changed.
7. **Same-clientId races undefined** — **Resolved**: same source + same clientId is idempotent (replaces pending); different source queues.
8. **Prompt spam via UUID rotation** — **Resolved**: one visible pending prompt per source address; spammers from one source replace, don't accumulate.
9. **Browser CSRF on pairing endpoints** — **Resolved**: `POST /v1/pair` requires `Content-Type: application/json`, rejects `Origin: null` and any browser Origin, rejects duplicate `Authorization`/`Content-Length` and any `Transfer-Encoding`.
10. **Server stores replayable plaintext tokens** — **Resolved**: only SHA-256 hashes stored on disk; plaintext exists only at issuance and during request validation.
11. **macOS encryption is fake protection** — UserDefaults-derived key is decryptable by any same-user process. **Resolved**: dropped the AES layer; rely on `0600` + hashed tokens. Documented honestly.
12. **"Yes once" persisted on CLI** — CLI wrote every token to disk. **Resolved**: status response includes `scope`; CLI keeps `session` tokens in-process only.
13. **Plain HTTP bearer replay** — accepted limitation. **Resolved**: documented honestly in UI/docs; users get session-scope guidance until TLS work lands.

### MEDIUM

14. **Revocation semantics incomplete** — **Resolved**: revoke deletes the pairing entry; next attempt re-prompts user.
15. **`DELETE /v1/pair?clientId=X` could revoke wrong client** — **Resolved**: server derives target from bearer token; query parameter ignored.
16. **Unauth prefix matching error-prone** — **Resolved**: exact-match decoded path against the three-entry allowlist.
17. **Header ambiguity** — **Resolved**: duplicate `Authorization`/`Content-Length` and any `Transfer-Encoding` rejected pre-routing.
18. **IPv4/IPv6 interface binding** — **Resolved**: bind/advertise only loopback + link-local + RFC1918; log accepted addresses.
19. **Device restart mid-pair** — **Resolved**: pending state is in-memory; restart → status returns `not_found`; CLI re-POSTs.
20. **Persistent store atomicity** — **Resolved**: temp + fsync + rename on all platforms.
21. **CLI token file handling** — **Resolved**: `~/.kelpie` created `0700`, symlinks rejected, world/group-readable files chmod'd or refused.
22. **Tokens leak via logs** — **Resolved**: centralized redaction of `Authorization` header, `token`/`bearer` body fields, and bearer-shaped regex in error messages.
23. **`clientName` attacker-controlled** — **Resolved**: truncated to 64 chars, control chars stripped, labeled "self-reported"; source IP from socket shown alongside as authoritative.
24. **"Always" too easy to mis-tap** — **Resolved**: `No` is default button (Return/Cancel); `Always` is visually distinct and never the default.

### LOW

25. **`device-info` naming drift** — design said `device-info`, codebase uses `get-device-info`. **Resolved**: design updated to `get-device-info` to match existing API.
26. **Cache control missing** — **Resolved**: `Cache-Control: no-store, no-cache` + `Pragma: no-cache` on all pair endpoints.
27. **CSPRNG not specified** — **Resolved**: design now explicitly requires `SecRandomCopyBytes` / `SecureRandom` / `crypto.randomBytes(32)`.

### Rejected / out-of-scope

None — all 27 findings were accepted and integrated. The non-codex reviewer also raised some overlapping points (token return on poll, revocation bypass, CORS); those are covered by the resolutions above.
