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

Hello advertises `browser.control` and implemented `page.extract` on Windows.
Device labels use the native computer hostname, bounded to 120 UTF-8 bytes without
splitting code points. Extraction summary, excerpt and source byte bounds use the
same boundary rule so multilingual page content remains valid JSON.

Only a short-lived UOA connection ticket reaches the fixed gateway. Tickets remain in
memory, are renewed before expiry, and a reconnect obtains a fresh ticket.401 gets the
account service's one forced access refresh;403 retains the account and asks for fresh
hosted consent.404,429, network and server failures retain the account and back off.
The new scope never widens a refresh grant. UOA must provision `kelpie.connect` for the
exact registered app and configure its gateway resource before connections can work;
see the [wire contract](nessie-connect.md).

Browser execution uses an explicit operation allowlist. It never forwards arbitrary
router calls, scripts, cookies, account settings or local-control credentials. Bound
requests share the existing DesktopMcpServer transaction, canonical reference
invalidation and unresolved renderer-operation fence with HTTP/MCP. No second
browser admission state is created. The transaction is released during model decoding
and reacquired before validating the original document/deadline after inference.
Snapshots reuse the common generated value-free reader in its native private world;
transient observed nodes provide bounded CSS selectors for the existing Nessie wire.
Editable values and raw accessibility trees are not forwarded.
operations use the named tab's current document version, activate that tab visibly,
and retain its lease through native owner-thread execution. Person-driven tab selection
pauses active work; bound owner-thread calls also require the target to remain active. Document versions change
on main-frame load, including same-URL reload, and are independent of tab lifetime.
Queued effects also carry cancellation and immutable full job deadline guards.
Individual browser calls remain bounded to ten seconds; local inference retains the
original job deadline and cannot extend it when returning to the browser. Inputs mirror the native
wire contract: selector clicks, atomic field fill, bounded scroll deltas, compact page
snapshot and optional viewport PNG. PNGs beyond the terminal-output budget fail with
`SCREENSHOT_TOO_LARGE`; full-page capture is unsupported here. HTTP(S) navigation rejects
embedded credentials and UOA account surfaces. Current private account-login windows
are outside the normal tab set.

Windows reports extraction readiness only while its embedded native text model is loaded.
Installed state checks the persisted local model path even when the model is unloaded.
Configured remote inference endpoints do not establish device-local model readiness.
Extraction uses bounded untrusted page text and a question, with no browser tool loop.
Its result contains a summary and URL/excerpt/time evidence with the pinned tab and
document version. Cancellation, deadline, active tab and document are checked again
after inference. Socket loss cancels in-flight work before any reconnect dispatch.
Windows inference binds the remote job's transient cancellation identity under a
request ownership lock. Pausing, stopping or losing that connection cancels only
its own inference; a person's independent tab chat remains untouched.
Control changes capture that cancelled request identity while changing state, so
a concurrent Resume and new command cannot redirect an older cancellation.
Backend selection is checked inside the inference lock so extraction cannot race a switch
to a cloud endpoint. Native decoding also polls a request-owned authority flag,
including model startup. Cancellation receipts for other job/attempt identities
are durably acknowledged without cancelling the active job.
Linux advertises no extraction/model capability. Heartbeats publish model readiness changes without reconnecting. The platform's existing inference UI owns model
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

GTK viewport resize/reset uses the current allocated browser widget dimensions,
independent of missing or stale CEF paint frames. Native Linux acceptance exercises
resize immediately after readiness and again after browser actions.

Verified on 2026-10-11 at source `3886012cfe0ca01560402d46557a0df3d27a3266`:

- Minis built Windows 0.1.12 Release with MSVC 19.51, pinned sandboxed CEF 152
  and embedded llama.cpp. All 50 CTest cases passed (15.55 seconds).
- Ubuntu 24.04.5 (`umac`, dedicated checkout) built Linux 0.1.10 Release with
  CEF 120/GTK. All 31 CTest cases passed (1.67 seconds). Both builds used
  concurrency two and existing dependency caches.
- The extracted Windows ZIP passed the real native acceptance runner: HTTP/MCP,
  input, screenshots, browser state, partition isolation, profile locking, occupied
  ports, session restore, graceful readiness cleanup, CLI alias and the built Nessie
  MCP client. Renderer process tokens proved the CEF sandbox was active. Linux's
  real native acceptance passed HTTP/MCP, trusted input, screenshots, partitions,
  profile ownership, session restore and readiness cleanup.
- Mocked gateway tests cover durable replay/receipts, current deadline admission,
  loss-induced cancellation, unrelated cancellations, and overlapping Pause/Resume
  with an older cancellation callback. Executor tests cover document drift,
  Unicode bounds and immutable full job deadlines.
- Windows ZIP and Linux tar.gz, DEB, RPM and AppImage candidates were generated
  by the existing release scripts. ZIP SHA-256:
  `12849b9e4b98db06b3fa101b4f887697ca8e2371d8823e488de2b1078eddbff9`.
  Logs, artifact checksums and source revision are preserved outside the checkout
  in `C:/Users/ondre/.codex/artifacts/kelpie-connect-20261011/desktop`.

Production UOA verification used an isolated current-user encrypted profile and
the existing AccountService native registration, normal PKCE loopback and visible
hosted consent. It obtained the app's `kelpie.connect` grant and a real 120-second
ticket with the exact Nessie audience; app identifier, scope and token-use claims
were checked in memory. The temporary helper exited normally before the packaged
Windows browser opened that same profile. The safe `verification-proof.json`
contains registration/scope/audience/TTL facts only, never the bearer or profile.

The packaged Windows browser loaded a 105,454,432-byte SmolLM2-135M-Instruct Q4_K_M
GGUF via the existing authenticated `ai-load` API into that isolated profile.
The [official base model](https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct)
and [quantization card](https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF)
declare Apache-2.0. Download revision `09816acd5d99df7be770d85ea30822623dab342c`
and file SHA-256 `2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d`
are recorded with the artifact. With context 2048 and two threads, the synthetic
page question returned “The verification lantern is blue.” using six generated
tokens in 86 ms, with backend `native` and loaded/installed state true.
`test_local_inference <GGUF>` also passed. Weights remain in the verification
artifact cache and are neither bundled nor automatically downloaded by the product.

These candidates are unpublished. The current Windows release workflow has no
Authenticode step; the bootstrap/app report `NotSigned` despite the verified CEF
sandbox. Linux packages were built/inspected on Ubuntu 24.04, without claiming
Ubuntu 22/Fedora matrix builds or system installation. Rendered account menus,
live production WSS dispatch/revocation and full page-extraction jobs remain
separate checks pending the coordinated Nessie deployment. The small model check
proves native execution, not general answer quality or a measured cloud-token saving.
