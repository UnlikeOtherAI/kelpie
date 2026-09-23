# Windows: an occupied control port refuses the second instance

## Problem

On 2026-09-23 `netstat -ano` showed two Kelpie PIDs both `LISTENING` on
`127.0.0.1:8420`. Connections were split between the two processes, so a
request carrying one instance's bearer token could reach the other one. The
second instance had also published a readiness file for a port whose
connections it did not reliably receive.

Reproduced on an unfixed build of `b83b954` with `--port 8441` and two
profiles: both instances published readiness and both appeared in
`netstat -ano` as `LISTENING` on `127.0.0.1:8441`. In that run every fresh
connection was accepted by the first instance: 60 of 60 requests carrying the
second instance's bearer token reached the first process and got `401`, so the
second instance's authenticated `close-browser` never reached it and it had to
be terminated.

## Root cause

`native/engine-chromium-desktop/src/desktop_http_server.cpp` binds with
cpp-httplib's default listener options (it never calls `set_socket_options`).
The Windows build compiles cpp-httplib v0.18.3 — `native/core-ai` declares that
tag before `apps/windows/CMakeLists.txt` and `native/engine-chromium-desktop`
declare v0.18.5, and the first declaration wins — but both releases have the
same `default_socket_options`:

```cpp
#ifdef _WIN32
  setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, ...);
  setsockopt(sock, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, ...);
#else
  setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, ...);  // or SO_REUSEADDR
#endif
```

Windows rejects `SO_EXCLUSIVEADDRUSE` with `WSAEINVAL` (10022) once
`SO_REUSEADDR` is set, and the socket keeps `SO_REUSEADDR=1`,
`SO_EXCLUSIVEADDRUSE=0` (measured with .NET sockets on this machine). A second
`SO_REUSEADDR` socket — the next Kelpie — then binds the identical address.

Measured bind matrix on Windows 11 26200, first listener on `127.0.0.1:P`
already listening, second socket binding the same address:

| First \ second | default | `SO_REUSEADDR` | `SO_EXCLUSIVEADDRUSE` |
|---|---|---|---|
| default (Node's listener) | `WSAEADDRINUSE` | `WSAEACCES` | `WSAEADDRINUSE` |
| `SO_REUSEADDR` (today's Kelpie) | `WSAEADDRINUSE` | **binds and listens** | `WSAEADDRINUSE` |
| `SO_EXCLUSIVEADDRUSE` | `WSAEADDRINUSE` | `WSAEACCES` | `WSAEADDRINUSE` |

A wildcard `0.0.0.0:P` bind still succeeds beside any of these, and an
exclusive `127.0.0.1:P` bind succeeds beside an existing wildcard holder
(default or `SO_REUSEADDR`), but Windows delivers `127.0.0.1:P` connections to
the more specific listener: 30 of 30 went to an exclusive `127.0.0.1` listener
with a `SO_REUSEADDR` wildcard listener beside it. The CLI, the readiness
record and the harness all dial `127.0.0.1`. This is unchanged by the fix.

This is why `verifyOccupiedPort` in the release harness never caught it: it
holds the port with a Node server, which libuv binds with default options, and
a default socket already refuses a `SO_REUSEADDR` bind. Only a shareable holder
such as a second Kelpie exposes the defect.

A second, independent defect hides the stage: `DesktopApp::Start` binds the
listener inside the CEF start, so a failed bind is reported as
`Browser startup failed during Chromium browser setup: The loopback control
listener did not start`. The `kHttpListener` stage in `windows_runtime.cpp`
only checks `bound_port() <= 0` after a successful start, which cannot happen,
so that failure path is dead.

## Fix

1. `DesktopHttpServer::Start` sets the listener options before binding. On
   Windows it sets only `SO_EXCLUSIVEADDRUSE`; elsewhere it calls
   `httplib::default_socket_options` so POSIX behaviour is unchanged in this
   change. An exclusive socket refuses both a later `SO_REUSEADDR` socket and a
   later exclusive one, and it cannot bind over a shareable holder either.
2. `DesktopApp::Start` no longer binds the control listener. A new
   `DesktopApp::StartListener()` binds `config.port` on `config.bind_host`
   (and starts mDNS when configured). Windows calls it at the `kHttpListener`
   stage, after the browser child is attached and before readiness
   publication, so the stage order matches the plan in
   `2026-09-15-windows-visible-browser-remediation.md` (CEF browser, bound HTTP
   listener, readiness publication). A failed bind takes the existing
   `kHttpListener` failure path: `Fail(kHttpListener, last_error)`,
   `ShutdownDesktopRuntime()`, and no `PublishReadiness`. The profile's own
   stale readiness was already removed by `ProfileSession::Open`, and
   `ClearReadiness` only ever removes this launch's record, so the holder's
   readiness file in its own profile is untouched. `BeginShutdown` stops mDNS
   only while the listener runs, since mDNS never started without one.
   `StartListener` refuses a second call, or a call before `Start`, with its
   own message rather than a port error.
3. The failure keeps the current visible-failure design: the window stays open
   and reads `Browser startup failed during local control listener: Could not
   start the control listener on 127.0.0.1:<port>; another process may own the
   port`. `StartListener` composes that from its config; `DesktopHttpServer`
   reports only a boolean, so the text does not claim to know which of bind or
   listen failed. A visible window does not exit on its own, exactly like the
   other post-shell startup failures; closing it exits with status 1. A launch
   whose window is hidden has nobody to read that, so it exits with status 1 at
   once (main's `WindowsApp::Run` rule, which this change leaves as it is).

Windows does not fall back to another port; the docs that describe port
fallback are scoped to the platforms that do it.

## Tests

- New Windows-only CTest `test_desktop_http_server_exclusive_port`:
  a `SO_REUSEADDR` holder (what an unfixed Kelpie creates) makes
  `DesktopHttpServer::Start` fail; a running server makes a second server fail
  and makes a later `SO_REUSEADDR` bind fail with `WSAEACCES`; after `Stop`,
  including after serving a request, a new server can bind the same port.
- `tests/windows/run-release-acceptance.mjs` `verifyOccupiedPort` takes a
  holder and runs against three: a `SO_REUSEADDR` .NET socket held by a
  PowerShell child (first, because it is the one a shareable listener binds
  beside), the existing Node server, and the running primary `kelpie.exe`.
  For each it asserts the contender publishes no readiness file (failing at
  once, with "shares the port", if it does), shows the local control listener
  failure in its window, and never owns a `LISTENING` socket on the port; the
  holder keeps its port, and the Kelpie holder keeps its readiness file and
  still answers with its own token. The runner then sends the contender's
  window `WM_CLOSE` and requires exit status 1, which exercises the failed
  listener's teardown. The old assertion that the contender exits by itself
  within 8 s predates the visible-failure design and never matched this build.
- Only a visible window shows the failed stage, so the occupied-port
  contenders are launched visible, with a seeded small corner placement; every
  other harness launch stays hidden. One further hidden contender against the
  running `kelpie.exe` must exit within 8 s with status 1, with the same
  readiness and `netstat` checks. (This branch first launched every harness
  browser visibly to get past `IsActiveNativeBrowserAttached`'s
  `IsWindowVisible` check; main has since fixed that check to read the child's
  own `WS_VISIBLE`, so that workaround was dropped when main was merged in.)
- The harness's CLI phase launches its alias on the run's `--port`. Without it
  the CLI uses `8420`, which a developer's own Kelpie usually holds; before the
  fix that launch would have shared the developer's port.

## Verification

On Windows 11 26200, built with `scripts/build-windows.ps1` (CEF 152 minimal,
`USE_SANDBOX=ON`) into this worktree, instances on `--port 8441` with their own
profiles; no other Kelpie was touched.

- CTest: 37/37 passed, including `test_desktop_http_server_exclusive_port`.
  The same test against the unfixed server fails at its first assertion.
- Two instances, first then second, each run to readiness or failure:

  | First | Second | Result |
  |---|---|---|
  | unfixed | unfixed | both `LISTENING` on 8441, both published readiness |
  | fixed | fixed | second fails at the local control listener, no readiness |
  | unfixed | fixed | second fails at the local control listener, no readiness |
  | fixed | unfixed | unfixed second is refused (reported as Chromium setup) |

  Each refused window closed on `WM_CLOSE` with exit status 1.
- Release harness, fixed build: launch, profile lock and all three occupied-port
  holders pass, then it fails at `evaluation must describe non-finite values`
  (`NaN` comes back bare instead of `{type: "nonfinite"}`), which is in the
  evaluate path this change does not touch. A local copy that logs that
  failure and continues also passed the sandbox check, authenticated close,
  the CLI launch/navigate/Nessie stdio MCP/stop phase on `--port 8441`, and a
  clean restart on 8441 with the same device id; session restoration was
  skipped because it depends on the failed phase.
- Release harness, unfixed build: fails at `launch against a SO_REUSEADDR
  listener published readiness, so it shares the port`.

## Out of scope, reported

POSIX keeps cpp-httplib's `SO_REUSEPORT`. On Linux that lets two same-user
listeners bind one address and the kernel splits connections between them
(measured in WSL2, two processes: 34/26 of 60 connections). No shipped POSIX
app runs `DesktopHttpServer` today — `apps/linux` has its own raw-socket server
with `SO_REUSEADDR` only and port fallback, and the Apple apps use Swift
listeners — so it is latent, and it gets its own change.

## Cross-Provider Review

Adversarial review of this design and the four code files it touches, run with
`kimix exec` (provider kimi, model k3-256k) before implementation; read-only,
no files changed. Assessment of each finding:

1. **mDNS `Stop` before `Start` (medium) — accepted.** With the split,
   `running` is true before any listener exists, so a failed `StartListener`
   followed by `Stop` would call `DesktopMdns::Stop` on a never-started
   advertiser. No `DesktopMdns` implementation exists and Windows passes none,
   but the contract should not depend on that: `BeginShutdown` now stops mDNS
   only while the listener runs.
2. **`last_error` provenance and wording (medium) — accepted in part.**
   `StartListener` composes the message from its config, and it now says
   "Could not start the control listener on 127.0.0.1:<port>; another process
   may own the port", which is true for both a refused bind and a listener
   loop that never started. Distinguishing the two would need
   `DesktopHttpServer` to report a reason; nothing needs that distinction, so
   it was not added.
3. **No test for the new `DesktopApp` states (medium) — accepted in part.**
   `DesktopApp::Start` needs a live CEF engine, which no CTest starts, so there
   is no unit test for it. Callers were audited: `windows_runtime.cpp` is the
   only one. The failed-listener teardown is covered end to end instead: the
   harness now sends each port-conflicted window `WM_CLOSE` and requires exit
   status 1, which runs `Stop` on exactly that state.
4. **No wildcard holder (low) — measured, not added to the harness.** An
   exclusive `127.0.0.1:P` bind succeeds beside an existing `0.0.0.0:P`
   holder, and loopback connections still reach the specific listener (30 of
   30). That is the same before and after the fix and cannot split the control
   plane, so it is recorded above rather than pinned in the harness.
5. **Window-text check is flaky (low) — rejected.** The stage is the
   requirement, and the window is the only place a failed launch reports it.
   The text is read with `GetWindowText` on the shell's own `Static` label and
   polled until it appears; the objective checks (no readiness, no listener)
   run alongside it and fail first and faster when a port is shared.
6. **Double `StartListener` (low) — already handled.** It refuses a second
   call, or a call before `Start`, with its own message.
7. **POSIX left on library defaults (low) — agreed, no change.**
8. **Shutdown and drain on the failure path (low) — agreed, no change.**
