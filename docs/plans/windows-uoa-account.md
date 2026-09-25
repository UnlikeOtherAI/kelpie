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

## Direct login/register follow-up

The signed-out account button currently always opens a descriptive menu, adding
an unnecessary click. Linux also picks a hard-coded browser rather than the
configured default, and no-browser launch failure stops authentication.

Change the signed-out button on Windows, Linux and Mac to start authentication
directly; retain a compact signed-in menu and pending-login cancellation. Use
“Login/register” for signed-out accessible labels and remove provider jargon.
Windows resolves the HTTPS association; Linux uses GIO's default HTTPS handler.
If no external handler can launch (or it resolves to Kelpie itself), the shared
account service queues the authorization URL for its owner-thread pump to open
in a transient isolated Login/register tab. Cancellation clears queued URLs;
repeated clicks do not create duplicate attempts. Existing PKCE/callback checks
remain unchanged. Mac retains its OS authentication session.

Test external-success versus fallback, duplicate clicks, cancellation before
handoff, and the unchanged OAuth callback. Build on each native host and release
only affected desktop versions. No CLI changes are needed.

### Follow-up cross-provider review

Claude's adversarial review identified that an ordinary isolated tab remains
agent-accessible. Accept that finding: the fallback is a separate, ephemeral
CEF login window outside the engine tab registry, history, DevTools and MCP
surfaces. It renders the hosted authentication page, never a native login form.
Move the entire browser handoff to the owner-thread Poll, including launching
the system browser; clear pending handoffs on cancellation and report a failed
handoff immediately. Close the private window on every terminal outcome and
wait for its CEF close callback before engine shutdown. Detect absent/default-
Kelpie handlers before launching, and remove the hard-coded Edge/Linux choices.
Preserve pending cancellation controls. Fix the listener startup/cancel race
with a readiness handshake and cover early cancellation in tests.

The authentication server's current public OAuth profile synthesizes a neutral,
password-only config. Merely enabling a Google button would not connect the
existing confidential social flow to public PKCE code issuance. The branded
config must be selected and verified server-side; neither its signing key nor
a domain bearer credential belongs in the app. Resolve the existing product
config before changing this server contract. Embedded-provider restrictions
still apply; the system browser remains the first choice.
