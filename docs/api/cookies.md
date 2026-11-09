# Kelpie API — Cookies

Kelpie reads and writes the browser's native cookie store, HttpOnly cookies
included. Every cookie call works on one store. While the person is signed in to
Kelpie, the default store also holds the cookies synced from their other Kelpie
devices on the same network.

For protocol details, errors and MCP tool names, see [README.md](README.md). The
device-to-device sync protocol is in [cookie-sync.md](cookie-sync.md).

## Contents

- [Cookie stores](#cookie-stores)
- [Who can read synced cookies](#who-can-read-synced-cookies)
- [`getCookies`](#getcookies)
- [`setCookie`](#setcookie)
- [`setCookies`](#setcookies)
- [`copyCookies`](#copycookies)
- [`deleteCookies`](#deletecookies)
- [`getCookieSyncStatus`](#getcookiesyncstatus)

## Cookie stores

| Target | Store |
|---|---|
| neither `tabId` nor `partition` | The default (unpartitioned) store. This is the store cookie sync keeps in step across the person's signed-in devices |
| `tabId` | That tab's store: its partition's store, or the default store for an unpartitioned tab |
| `partition` | That partition's store. The id follows the [partition string rules](browser.md#newtab); a bad id returns `INVALID_PARTITION` |

Pass at most one of `tabId` and `partition`. `copyCookies` names two stores as
`from` and `to`; `{}` is the default store.

Partitioned stores never sync. Cookies reach a partitioned tab only when a caller
copies or writes them there.

## Who can read synced cookies

Every signed-in device's default store holds the synced set. **Any client paired
with any one device can therefore read and plant cookies for all of that
person's devices.** Cookies written into the default store with `setCookie`,
`setCookies` or `copyCookies` sync like any other change. Pairing and
authorization are unchanged; see [account pairing](account-pairing.md).

Some sites bind a session to one device, IP address or user agent and reject a
copied cookie. Kelpie writes it; the site decides whether to honour it.

---

### `getCookies`

Read cookies for the current page, or every cookie in a store.

```json
POST /v1/get-cookies
{
  "url": null,        // optional, keep cookies that would be sent to this URL
  "name": null,       // optional, filter by cookie name
  "all": false,       // optional, every cookie in the target store instead of the current page's
  "domain": null,     // optional, keep cookies whose host is this domain or a subdomain of it
  "tabId": null,      // optional, read this tab (see Cookie stores)
  "partition": null   // optional, read this partition's store
}

Response:
{
  "success": true,
  "cookies": [
    {
      "name": "session_id",
      "value": "abc123...",
      "domain": ".example.com",
      "path": "/",
      "expires": "2026-04-30T00:00:00.000Z",
      "httpOnly": true,
      "secure": true,
      "sameSite": "Lax"
    },
    {
      "name": "theme",
      "value": "light",
      "domain": "example.com",
      "path": "/",
      "expires": null,
      "httpOnly": false,
      "secure": false,
      "sameSite": "Unspecified"
    }
  ],
  "count": 2,
  "complete": true    // with all:true only
}
```

| Field | Meaning |
|---|---|
| `domain` | A leading dot marks a domain cookie; without it the cookie is host-only |
| `expires` | ISO-8601 expiry, or `null` for a session cookie |
| `sameSite` | `Strict`, `Lax`, `None` or `Unspecified` (the cookie has no SameSite attribute) |
| `complete` | Sent with `all:true`. `true` on macOS, iOS, Windows and Linux, which enumerate the whole store. `false` on Android: its WebView cannot enumerate cookies, so Kelpie reads the cookies for every URL it knows (history, recent pages and synced cookies) and may miss others |

Without `all`, behaviour is unchanged: the call returns the cookies the target
tab's current page would send. `url` scoping matches a cookie's host, path and
`Secure` flag against the URL, mirroring which cookies the browser would actually
send — equivalent to Android's `CookieManager.getCookie(url)`. `url`, `name` and
`domain` are honoured on every platform and combine.

To export the person's synced sessions, call `{"all":true}` with no target. To
see one site only, add `"domain":"example.com"`.

### `setCookie`

Set one cookie.

```json
POST /v1/set-cookie
{
  "name": "session_id",
  "value": "new_value",
  "domain": "example.com",
  "path": "/",
  "httpOnly": true,
  "secure": true,
  "sameSite": "Lax",
  "expires": "2026-12-31T00:00:00.000Z"
}

Response:
{
  "success": true
}
```

The cookie is written to the platform's native cookie store (`WKHTTPCookieStore` on
iOS/macOS, `CookieManager` on Android, Chromium's cookie store on Windows and Linux),
so `httpOnly`, `secure`, `sameSite` and `expires` are all honoured on every
platform. This is the supported way to inject an httpOnly session cookie for auth —
JavaScript (`eval` / `document.cookie`) cannot create httpOnly cookies. Pass `tabId`
to target a specific tab's cookie store.

### `setCookies`

Write a list of cookies into one store.

```json
POST /v1/set-cookies
{
  "cookies": [            // required, at most 500, in the shape getCookies returns
    { "name": "sid", "value": "…", "domain": ".example.com", "path": "/",
      "expires": "2026-12-31T00:00:00.000Z", "httpOnly": true, "secure": true, "sameSite": "Lax" }
  ],
  "tabId": null,          // optional target (see Cookie stores)
  "partition": null       // optional target
}

Response:
{
  "success": true,
  "set": 1,
  "failed": [             // cookies not written; the rest are still written
    { "index": 3, "name": "big", "domain": ".example.com", "error": "NOT_STORED" }
  ]
}
```

- With no target, the cookies go into the default store and sync to the person's
  other signed-in devices.
- Every field of each cookie is required. `sameSite` must be one of the four
  values above; `Unspecified` writes the cookie without the attribute.
- `expires` is ISO 8601 UTC, whole Unix seconds or `null` for a session cookie.
- `index` is the cookie's position in the request. `error` is `INVALID_COOKIE`
  (the cookie could not be built, for example an unparseable `expires`) or
  `NOT_STORED` (the engine did not keep it, for example `SameSite=None` without
  `Secure`). `failed` never contains a value.
- More than 500 cookies, or `cookies` that is not an array, fails the whole
  request with `INVALID_PARAMS` before anything is written.

The CLI's `kelpie cookies import` sends a saved listing in batches of 500.

### `copyCookies`

Copy cookies from one store to another on the same device. The values never pass
through the caller.

```json
POST /v1/copy-cookies
{
  "from": {},                  // required; {} is the default store
  "to": { "tabId": "tab-2" },  // required; {} is the default store
  "domain": "example.com"      // optional, only this domain and its subdomains
}

Response:
{
  "success": true,
  "copied": 12,
  "failed": [ { "name": "…", "domain": "…", "error": "…" } ]
}
```

`from` and `to` each take at most one of `tabId` and `partition`. The same store as
source and target returns `INVALID_PARAMS`. A `failed` entry's `error` is
`NOT_STORED` (the target engine did not keep it) or `PARTITIONED` (a CHIPS cookie
the source engine marks as partitioned; it is never copied). Cookies already in the target with
the same domain, path and name are replaced.

**Sign an isolated tab in with the person's sessions:**

1. `new-tab {"url":"about:blank","partition":"agent-1"}` → `tabId`.
2. `copy-cookies {"from":{},"to":{"tabId":"<tabId>"},"domain":"example.com"}`.
3. `navigate {"url":"https://example.com/","tabId":"<tabId>"}`.

The partitioned tab now has the cookies; it still never syncs. To bring cookies
from a partition back into the default store, copy with `{"from":{"partition":"agent-1"},"to":{}}`.
That write syncs to every signed-in device.

### `deleteCookies`

Delete cookies by name, domain, or all.

```json
POST /v1/delete-cookies
{
  "url": null,                // optional, scope deletion to cookies sent to this URL
  "name": "session_id",       // optional, delete specific cookie
  "domain": "example.com",    // optional, scope deletion to this exact domain
  "deleteAll": false          // optional, delete all cookies in scope
}

Response:
{
  "success": true,
  "deleted": 1
}
```

The `url`, `name`, and `domain` selectors are honored on all platforms. When none
of `name`, `domain`, or `deleteAll` is supplied, the call is a no-op (`deleted: 0`)
rather than wiping the store. `deleteAll` only clears the full store when no
`url`/`name`/`domain` narrows the scope; otherwise it deletes just the matching
cookies. `domain` matching is exact and tolerant of a leading dot.

While cookie sync runs, a small deletion from the default store, such as a site
logout, reaches the person's other devices. Deleting more than 20 synced cookies
that are also more than a quarter of the store at once — a clear-all, for
example — is treated as a purge: it clears this device only, and the other
devices keep their cookies.

### `getCookieSyncStatus`

Report peer-to-peer cookie sync on this device.

```json
POST /v1/get-cookie-sync-status
{}

Response:
{
  "success": true,
  "supported": true,
  "signedIn": true,
  "replica": "DrlGeFx11w1azJdmwzXszw",
  "listening": true,
  "peers": [
    { "replica": "OjJiVoGP30gQg8yzYiW6bQ", "platform": "ios", "name": "Kitchen iPad",
      "state": "connected", "lastSyncAt": 1731150012345 },
    { "replica": "q0W8fA1y3dXm2kLr9sT6uA", "platform": "windows", "name": "Office PC",
      "state": "clock-skew", "lastError": "CLOCK_SKEW" }
  ],
  "store": {
    "entries": 812, "tombstones": 40, "localOnly": 0, "unapplied": 1,
    "skipped": 0, "warming": false, "lastPurgeAt": null
  }
}
```

| Field | Meaning |
|---|---|
| `supported` | `false` when sync is not running here; `reason` says why |
| `reason` | `signed-out` (no UOA session), `embedded` (a browser inside another app), `webview-unsupported` (Android WebView without `GET_COOKIE_INFO`), `mdns-unavailable` (no mDNS, e.g. Linux without Avahi), `no-cef` (a desktop build without the Chromium engine), `store-unavailable` (the sync metadata file cannot be opened) |
| `replica` | This run's replica id. It changes on every launch and sign-in; absent while sync is not running |
| `listening` | Whether the sync-only listener accepts peers. A device that cannot listen, for example behind a firewall, still syncs by connecting out |
| `peers[].state` | `handshaking`, `connected`, `backoff` (retrying after a failure), `clock-skew` (clocks more than 2 minutes apart) or `failed` |
| `peers[].lastSyncAt` | Unix milliseconds of the last completed pull or push |
| `peers[].lastError` | Code of the last failure |
| `store.entries`, `store.tombstones` | Live cookies and remembered deletions in the sync metadata |
| `store.localOnly` | Cookies kept from a different UOA account on this device. They never sync |
| `store.unapplied` | Synced cookies this engine refused |
| `store.skipped` | Synced cookies ignored to stay under 150 per domain and 3 000 in total |
| `store.warming` | `true` for up to 30 s after launch while peers' cookies arrive |
| `store.lastPurgeAt` | Unix milliseconds of the last scan treated as a purge, or `null` |

The status reports counts only. It never names a cookie or a domain.
