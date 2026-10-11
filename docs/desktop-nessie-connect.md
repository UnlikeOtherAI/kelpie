# Windows and Linux account connection

The Chromium desktop apps open outbound TLS WebSockets to Nessie after their existing
UOA account session restores. The account menu is the owning surface: it shows live
Nessie connection/work status, Pause/Resume, Stop/Connect and the normal hosted sign-in
doorway for granting the new permission. Pause stops current work and keeps a paused
connection; Stop disconnects. Both choices persist across launches. Sign-out cancels
work and removes the prior account's journal. The Linux no-CEF fallback cannot connect.

The common implementation is `native/desktop-connect`, using `native/core-connect`'s
ledger and `native/desktop-account`'s existing rotating refresh lifecycle. A dedicated
encrypted blob store reuses the session store's atomic, flushed DPAPI (Windows) and
AES-GCM/file-permission (Linux) implementations, with separate journal/control names.
Journal corruption or persistence failure disables dispatch instead of starting an
empty ledger. Missing account state while launch restore runs preserves the journal.
Accepted/terminal events are persisted before sending, and a restart replays retained
terminal results; potentially effective interrupted work becomes `UNKNOWN_EFFECTS`.

Only a short-lived UOA connection ticket reaches the fixed gateway. Tickets remain in
memory, are renewed before expiry, and a reconnect obtains a fresh ticket.401 gets the
account service's one forced access refresh;403 retains the account and asks for fresh
hosted consent.404,429, network and server failures retain the account and back off.
The new scope never widens a refresh grant. UOA must provision `kelpie.connect` for the
exact registered app and configure its gateway resource before connections can work;
see the [wire contract](nessie-connect.md).

Browser execution uses an explicit operation allowlist. It never forwards arbitrary
router calls, scripts, cookies, account settings or local-control credentials. Bound
operations use the named tab's current document version, activate that tab visibly,
and retain its lease through native owner-thread execution. Document versions change
on main-frame load, including same-URL reload, and are independent of tab lifetime.
Queued effects also carry cancellation and deadline guards. Inputs mirror the native
wire contract: selector clicks, atomic field fill, bounded scroll deltas, compact page
snapshot and optional viewport PNG. PNGs beyond the terminal-output budget fail with
`SCREENSHOT_TOO_LARGE`; full-page capture is unsupported here. HTTP(S) navigation rejects
embedded credentials and UOA account surfaces. Current private account-login windows
are outside the normal tab set.

Windows advertises extraction only while its embedded native text model is loaded.
Configured remote inference endpoints do not establish device-local model readiness.
Extraction uses bounded untrusted page text and a question, with no browser tool loop.
Linux advertises no extraction/model capability. Model readiness changes reconnect to
publish the current capabilities. The platform's existing inference UI owns model
installation/loading; the Nessie connection never downloads or loads one implicitly.

## Verification

Configure the native platform build with `BUILD_TESTING=ON`, build bounded concurrency
and run CTest's `connect_executor_test`, `account_connect_test`, account session and
shared ledger tests. Focused cases cover current document pins, races, cancellation,
deadlines, URL restrictions, snapshot/extraction boundaries, unchanged refresh scope,
encrypted namespace isolation and result retention. Native Windows requires the pinned
sandboxed CEF SDK; Linux requires its CEF runtime, curl/OpenSSL and GTK for menu checks.
Portable mocks do not verify production provisioning, real WSS revocation, installed
model inference or the rendered platform menus. Those require native/integration checks.
