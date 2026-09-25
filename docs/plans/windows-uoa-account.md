# Windows UOA account and final tab colors

The user explicitly requested UOA sign-in and favorite sync, and then clarified
that inactive tabs and the entire title strip must stay static light gray on
both desktop platforms. Only the selected tab and navigation/favorites area
carry the sampled page color. Preserve native high-contrast overrides.

## Account architecture

Mirror the Mac public OAuth client: authentication.unlikeotherai.com,
openid profile settings.read settings.write, PKCE S256, random state, /oauth/me,
/oauth/me/avatar, and /oauth/me/settings/browser/bookmarks. Use the system
browser and a dedicated ephemeral 127.0.0.1 callback listener. Bind before
registration/opening; register the exact callback URI. Cache only the public
client ID and its callback port in the profile; if that port is unavailable,
allocate a new port and register a new client. Validate Host, path, exactly one
state/code, no error, constant-time state equality, and consume once. Cancel
and five-minute expiry close the listener. Never store tokens or account data
on disk or put them in the Kelpie renderer, history, logs, or agent APIs.

A Windows account service owns session state under a mutex, a generation to
invalidate late responses, a serialized operation mutex, and a bounded worker
for UI actions. API worker threads can call the same bookmark operations;
network work never blocks the CEF/UI thread. WinHTTP uses normal TLS validation,
no cookies or redirects, bounded timeouts and response sizes. Sign-out clears
memory immediately and makes late responses inert. A 401/expiry returns to
local favorites, while the failing mutation reports an error (never silently
writes locally). Shutdown cancels login and joins bounded account work before
runtime destruction.

Keep the shared local bookmark store unchanged. Add optional bookmark action
and current-list callbacks to DesktopApp config/runtime, used by existing
bookmark handlers and start-page data; absent callbacks preserve all platforms.
Windows routes signed-out operations to the existing local store, signed-in
operations to the account list. SaveStores always persists only that local
store. GET latest + ETag / If-Match PUT applies add/remove/clear intentions to
opaque JSON entries, preserving other clients' metadata. Retry conflicts at
most three times. Deduplicate additions by URL. Stable IDs for legacy entries
match the Mac SHA-256 URL fallback. Cloud failure must not erase visible data.

The toolbar account button shows an avatar or person icon and opens a native
menu with identity, sign-in/cancel, refresh favorites and sign-out; errors and
busy state remain visible. Add favorite uses the same account service as MCP.
No new agent account/login methods. Tests inject a fake transport to cover
PKCE callback validation, conflict merge/metadata, local/cloud separation,
expiry, stale generation, cancellation and failed mutations. Exercise the real
sign-in landing page without entering user credentials.

## Cross-Provider Review

The account implementation lives in native/desktop-account so Windows and Linux use the same state machine and merge behavior, with native WinHTTP and curl transports.

Review completed by Claude Code before account implementation. Accepted: exclusive
loopback bind, validated denial handling, callback limits, cancellation before
shutdown drain, token-type/scope checks, steady-clock expiry, nonblocking cached
start-page reads, preserving opaque JSON entries, one operation deadline,
case-insensitive stable IDs, and explicit local/account list switching. Favorites
are intentionally visible through the existing renderer and bookmark APIs;
credentials and profile/avatar are not. API operations bind to a generation.
The existing clear command retains its documented meaning for the selected list.

The suggested shared Swift/C++ merge migration and authentication-server changes
would expand this task substantially; the iOS/Android parity rule does not require
that refactor. Windows tests pin the Mac-compatible first 16 SHA-256 bytes, UUID
format and metadata-preserving intention semantics. Keep a cached public client
and loopback port; allocate/re-register only when that port cannot be bound.
No changes to the external authentication service are part of this task.
