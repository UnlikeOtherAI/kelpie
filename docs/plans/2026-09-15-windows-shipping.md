# Windows shipping plan

## Outcome

Ship a real Windows Chromium browser with working tabs, navigation, history autocomplete,
and the same browser actions available to local development agents and Nessie's MCP client.
Terra implements the changes in three coordinated batches. The orchestrator owns diagnosis,
design review, acceptance testing, PR review/merge, and release verification.

## Root causes established before implementation

1. `apps/windows` has a separate minimal CEF host and HTTP server. It does not use the
   shared desktop handlers and has no `/mcp` route. The advertised catalogue exceeds
   the runtime's roughly fifteen implemented endpoints.
2. Shared `BrowserManagementHandler::NewTab` overwrites tab 0. Switch and close return
   unsupported. Windows has no tab strip.
3. `HistoryStore::BestUrlCompletion` exists but the Windows URL edit never calls it.
4. HTTP worker threads call CEF directly; the Win32 loop only pumps CEF after a Windows
   message arrives. These violate CEF thread/liveness requirements.
5. Shared CEF evaluation executes JavaScript and returns an empty string. Windowed
   screenshots cannot rely on offscreen `OnPaint` buffers. Real result-returning browser
   evaluation and valid image capture are release requirements, not just route wiring.
6. Windows and shared desktop HTTP servers bind to unrestricted addresses with wildcard
   CORS and no authentication despite the documented authorization contract.
7. Windows CMake does not build the CEF wrapper; shared CMake only finds Linux libraries.
   There is no Windows CEF download/build/package script, CI job, or release asset.
8. Several Windows UTF-8/UTF-16 helpers allocate excluding the terminator but call the
   conversion with a source length including it. Navigation and profiles need Unicode tests.

## Architecture and invariants

Use one shared Chromium runtime, router, stores, and MCP implementation. Delete the
parallel Windows browser/server path when replacing it. Native Windows code owns window
creation, toolbar/tab strip, utility panels, profile paths, and lifecycle glue.

### Browser and tab contract

- One CEF initialization per application process, correct subprocess exit propagation,
  continuously serviced message pump, and orderly browser-close callbacks before shutdown.
- Runtime owns stable opaque string tab IDs, one active tab, per-tab URL/title/loading
  state, navigation history, and renderers. New tabs create separate browsers. Closing the
  last tab leaves one blank usable tab. Popups enter the same tab model.
- Provide a platform-neutral `DesktopBrowserControl` seam for list/create/activate/close,
  navigation, and explicit tab lookup. Calls marshal to the CEF UI thread with bounded
  completion; browser callbacks can resolve operations without blocking that thread.
- Page operations accept `tabId`. Invalid IDs fail. With multiple tabs, omitted `tabId`
  returns `TAB_REQUIRED` instead of letting concurrent agents affect an arbitrary tab.
  Explicit background-tab operations do not change the visible selection.
- API success means the operation succeeded. Evaluation returns actual typed results and
  script exceptions; navigation reports timeout/failure. Screenshots contain valid PNG/JPEG
  bytes. No synthetic success or empty data disguised as completed browser work.
- Persist URLs, stable IDs, and active selection in the profile using atomic replacement.
  Restore tolerates invalid/corrupt entries and does not revive closed tabs. Each profile
  has one owner; a conflicting launch fails clearly instead of sharing Chromium storage.
- Read/mutate tab state on its owner thread. Never hold a global lock while waiting for a
  callback that needs that lock. Shutdown cancels pending commands before destroying state.

### Native interaction

- Tab create/switch/close in the strip and Ctrl+T/Ctrl+W/Ctrl+Tab/Ctrl+Shift+Tab shortcuts.
- URL entry, Ctrl+L, Enter navigation, back/forward, reload/stop, page-driven navigation,
  browser focus, resize, and fullscreen remain synchronized with the active tab.
- Reuse `BestUrlCompletion` for history completion. Preserve the typed prefix and select
  only the completion suffix. Deleting/rejecting a suffix must not immediately reinsert it;
  Ctrl+A, paste, selection edits, Unicode, Enter, and Escape must behave predictably.
- Bookmarks/history/network/settings use the shared state and actions, with equivalent
  HTTP/MCP controls for browser-owned state and no extra agent-only UI.

### HTTP, MCP, and agent access

- Default Windows automation is local-only on loopback. Reject browser `Origin` headers
  and non-loopback `Host` values, remove wildcard CORS, bound request bodies and waits,
  and bind the actual port before reporting readiness. Remote unauthenticated listening
  is forbidden. Do not advertise a LAN address as usable for a loopback-only service.
- Report the local-only trust boundary honestly in capabilities/device info/docs. Remote
  access must have an implemented pairing/token boundary before it can be enabled.
  Local development and a local Nessie executor use the local capability-token handoff below.
- `/mcp` supports initialization, notifications (no JSON-RPC reply), ping, tools/list and
  tools/call with usable input schemas. Validate envelopes and arguments, correlate IDs,
  return protocol/tool errors correctly, and expose only callable tools.
- One route/capability source determines HTTP handling, browser MCP discovery, and the CLI's
  runtime support checks. Platform availability alone is insufficient to claim support.
- Required working actions: tabs and navigation; eval/DOM/text/accessibility/find; click,
  fill, typing, keypress, scroll, waits; screenshots; cookies/storage; dialogs; viewport;
  console/network inspection; bookmarks/history/home; native fullscreen and toast.
  Unimplemented platform-specific features must be explicitly unsupported, never advertised
  as operational. Gaps in this frozen required set are release findings.
- CLI Windows browser discovery/launch/install uses published portable artifacts and stable
  user-owned paths, supports paths with spaces and distinct profiles, and propagates launch
  failures. Verify actual Nessie stdio/HTTP client behavior against Kelpie; an example alone
  is insufficient. Keep adjacent Nessie source read-only unless a necessary change is planned.

## Implementation batches

### A — Runtime, Windows lifecycle, and distributable (Terra)

Own Windows bootstrap/app lifecycle/profile ownership/browser attachment, shared CEF
engine/renderer/tab control, CMake, permanent Windows build/download/package scripts, and
Windows CI. Replace stub wiring, repair lifecycle, implement real tabs and results, and
persistence. Pin a Windows
CEF SDK with recorded upstream checksum. Build wrapper and include all runtime/locales/licenses
and required redistributable DLLs. A release build must fail if CEF/runtime assets are absent.

### B — MCP, CLI, and integration contract (Terra)

Own shared `DesktopApp`, router, HTTP/MCP transport, handlers, CLI/shared TS definitions and
tests. Consume the agreed runtime control seam, implement missing required browser actions,
fix capability/schema drift and local security boundary, test Nessie's real client, and add
durable transport plus Windows lifecycle/agent flow tests. Update API/CLI/functionality docs.

### C — Native controls and release qualification (Terra)

Own the Win32 shell, URL bar, tab strip, utility panels, shared Windows Unicode helper,
and the durable Windows acceptance harness. Implement tab controls and shortcuts, focus,
autocomplete, and actionable native panels against the runtime delegate. Freeze delegate
additions with A before editing; A retains lifecycle and build files. Exercise actual
Nessie client stdio attachment without relaxing its default network policy. Product UI/
executor integration in Nessie is separate from this client compatibility gate and must
be planned explicitly before changing that repository.

The agents coordinate shared interfaces before editing. Handler tests use the frozen
browser-control interface with a mock while the real CEF implementation is being completed.
Each works only in its own
`.worktrees/` checkout. Cohesive dependent work may use stacked PRs; merge a PR only after it
builds and its behavior is verified. Avoid a sequence of tiny unreviewable patches.

## Acceptance and release gates

1. Windows Release CEF build, targeted native tests, and CLI `pnpm lint`, `pnpm build`,
   `pnpm test`. Run CI for affected shared components; keep Apple/mobile contracts unchanged.
2. Deterministic local fixture flows over direct MCP and CLI stdio: navigate/link/back/forward/
   reload, real eval/errors, form/keyboard/scroll, screenshot decoding, dialogs, cookies and
   storage, console/network, bookmarks/history, viewport, and invalid request handling.
3. Several independent tabs, repeated create/switch/close, background targeting, duplicate
   URLs, popup handling, close-last-tab, rapid commands, navigation cancellation, invalid IDs,
   occupied port/profile, Unicode paths/text, clean shutdown and restoration.
4. Native UI inspection with actual keyboard/mouse: chrome after page focus, tabs, URL
   synchronization, autocomplete acceptance/deletion, settings and utility panels, resize.
5. Nessie client initialize/list/call/text+image flow using its actual MCP library/protocol.
6. Adversarial code review and security checks: browser-origin/host attacks, malformed JSON,
   invalid types, body/timeout bounds, advertised-versus-callable inventory, lifecycle races.
7. Version only affected components, immediately push each commit, PR/review/merge, then
   publish Windows portable ZIP and npm packages if changed in a date-tagged GitHub release.
   Download/install the published artifacts and repeat core UI/MCP/CLI acceptance. Record
   versions, checksums, passed tests, and unverified limits. Remove merged local/remote branches.

## Cross-Provider Review

Completed before implementation on 2026-09-15 by Claude (Opus 5 High, desktop chat titled
"CEF sandbox and security configuration review") and an independent Terra reviewer.
Claude reviewed the complete plan; Terra also inspected the existing source. The CLI
Claude login was unavailable, so the already authenticated desktop supplied the review.

### Accepted amendments (binding implementation details)

1. **Chromium sandbox:** Windows production builds must use the supported sandbox-enabled
   CEF launcher described in the amendment below. The client and wrapper must use matching
   CRT settings. `no_sandbox` is forbidden in the shipped Windows artifact. Failure to
   build/run the sandbox is a release blocker.
2. **Local authorization:** Create a cryptographically random per-launch bearer token in a
   readiness file protected by a Windows ACL for the current user (and OS administrators).
   The HTTP server validates it for all control and MCP routes. Only discovery/health may
   be public, with no page/profile secrets. Loopback, Origin, Host, and JSON-content gates
   remain defense in depth. CLI local discovery/launch reads this file only for the current
   user's configured profile and binds the credential to device identity and bound port.
   CLI stdio hides this handoff from Nessie. No remote-control switch ships in this release.
   A supplied/profile-selected readiness path permits multiple explicitly named profiles;
   launching into an occupied profile fails clearly. Never put tokens in stdout or logs.
3. **CEF ownership:** Execute subprocess dispatch before any app shell/profile/network
   initialization and propagate its exact exit status. One shared CefApp owns CEF. Use an
   external message pump on the Win32 owner thread: `OnScheduleMessagePumpWork` posts to
   that loop, with a coalesced timer that continues pumping during modal move/size/menu
   loops. Shutdown waits for browser close callbacks before `CefShutdown`.
4. **Request lifecycle:** Freeze the `DesktopBrowserControl` header before both batches use
   it. Represent failures/timeouts/cancellation explicitly. Each command resolves a stable
   tab lease/generation for its whole operation; no global `HandlerContext::SetRenderer`
   swapping. Timeouts invalidate queued work and late replies; closed IDs are never reused.
   Already-dispatched page side effects cannot be undone and must be documented as unknown
   on timeout. Close/shutdown reject pending and future work without dangling references.
5. **Browser mechanisms:** Use CEF DevTools result callbacks for `Runtime.evaluate` with
   `returnByValue` and `awaitPromise`, and `Page.captureScreenshot` for encoded images of
   background/windowed tabs. Return JSON values, explicit descriptors for undefined and
   non-JSON results, and real JavaScript errors. Never use `PrintWindow` as browser capture.
   Cookies use `CefCookieManager` with actual httpOnly/secure/sameSite/expiry attributes.
   Input uses native CEF or DevTools trusted events; selector lookup supplies geometry.
   Remove persistent page bridge monkeypatching; observe console/network natively.
6. **MCP transport:** Stateless Streamable HTTP is sufficient: POST JSON replies, HTTP 202
   with no reply body for valid notifications, GET 405 when no SSE stream is offered,
   explicit negotiated version handling, and bounded envelopes and tool arguments. CLI
   stdio emits only protocol JSON on stdout. Test actual SDK initialization and tool calls.
7. **Profile safety:** Hold an OS exclusive file handle for the profile lifetime; never
   rely on PID files. Persist ordered snapshots via same-volume temp + flush + Windows
   replace/move APIs. Serial writes must not let older state overwrite newer tab state.
8. **Autocomplete/Unicode:** Share one conversion helper with explicit input lengths and a
   defined invalid-input error/replacement policy. Complete only when insertion happens
   at end of text with no prior selection; never on deletion. Match Unicode exactly where
   the existing store lacks Unicode case folding; do not add a new Unicode dependency.
9. **Verification:** Include trusted input events, real image decoding, cookie flags,
   stale operations after close, bad origins/hosts/tokens/types, and advertised tool
   reachability in durable tests. Use an automated Windows CEF fixture plus visible native
   UI checks. Update architecture, stack, browser-engine, and security docs as appropriate.

### Findings assessed without adding complexity

- Keep the existing macOS-compatible `TAB_REQUIRED` contract when multiple tabs exist.
  It fails safely and is recoverable by listing tabs; forcing IDs even for one tab or
  adding per-connection active tabs would break existing clients or add mutable state.
- Use shared native tool contracts with real schemas and callable checks plus cross-language
  parity tests. A new universal code generator for all platform routers/types is out of
  scope and would increase complexity during this repair.
- Freeze the header between the two agents, then land coherent tested runtime/transport
  work. Do not add a separate interface-only PR just to enable the parallel workflow.
- The current CEF sandbox requires the same bootstrap executable for the browser and all
  subprocesses. Keep `browser_subprocess_path` empty and dispatch subprocesses immediately.
- The required action list above is the frozen Windows release scope. Unsupported
  platform-only actions stay explicit. Additional findings are triaged by impact rather
  than expanding the release to reproduce every mobile feature.
- Nessie is present at `C:\Users\ondre\Projects\Nessie`; the reviewer's absent-checkout
  concern was incorrect. The integration agent is inspecting its real MCP client.

### Current CEF sandbox amendment

The pinned CEF 152.0.6 Windows SDK follows the M138-and-newer distribution model.
The initial review's suggestion to link `cef_sandbox.lib` into an ordinary MSVC app
does not apply: that library now depends on Chromium's internal toolchain and is not
distributed. See [official CEF sandbox setup](https://chromiumembedded.github.io/cef/sandbox_setup.html)
and the pinned SDK's `include/cef_sandbox_win.h`.

- Package the supplied sandbox-enabled `bootstrap.exe` as `kelpie.exe`, alongside
  the application built as `kelpie.dll` and the matching CEF runtime assets.
- Export the exact pinned `RunWinMain` signature, including `sandbox_info` and
  `cef_version_info_t*`. Follow the SDK's version compatibility handshake.
- Forward the bootstrap's sandbox pointer to both `CefExecuteProcess` and
  `CefInitialize`. Run dispatch before profile locks, app windows, or HTTP startup.
- Keep `browser_subprocess_path` empty: CEF sandbox requires the same executable
  for browser and subprocesses. Missing bootstrap assets fail the shipping build.
- Preserve matching client/wrapper CRT configuration. Do not attempt to recreate
  Chromium's toolchain or substitute an older vulnerable CEF to regain static linking.
- Validate renderer sandbox state in the running packaged artifact, in addition
  to checking that the build and command line contain no sandbox-disabling path.
- Bootstrap resource/version customization must use a repeatable build step;
  package verification checks both executable and client version metadata.

This corrects the implementation mechanism while preserving the reviewed sandbox-on gate.
Claude completed an adversarial amendment review in the same desktop conversation before
bootstrap implementation. Accepted findings: verify the exported C ABI symbol, preserve
bootstrap-owned pointer lifetimes and POD-only boundaries, use the DLL module handle for
application resources, audit DLL/global initialization for subprocess side effects, fail
on mixed SDK/bootstrap versions, check the running renderer sandbox, and retain stable
`kelpie.exe`/`kelpie.dll` names. Package checksums distinguish original bootstrap bytes from
any customized artifact. Installation must use a current-user-owned directory; this does
not defend against another process already running as that same user.

Review corrections: including the pinned `cef_sandbox_win.h` declaration provides C
linkage, so a separate `.def` file is only needed if export verification shows it necessary.
Validate the incoming version structure's size before reading fields; do not overwrite
the size of a bootstrap-owned allocation. Keep this release Windows x64 and report that
architecture explicitly. Resource changes precede any available code-signing step.
