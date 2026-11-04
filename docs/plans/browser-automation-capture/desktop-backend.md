# Desktop capture and restricted worker backend

Owner: desktop-backend. Audited base: b6784ff723b27da4096fdd8d9227f2a00dfc9084.
Branch: codex/capture-desktop-20261104.
Worktree: D:/Worktrees/kelpie/capture-desktop-20261104 on Maxis.
This checklist records planned work and evidence, not completed platform support.

## Rollout ownership and gate

The user changed rollout priority to Windows on Maxis first, then Mac. The
coordinator reassigned Windows native capture to the macOS worker after the initial
audit; this owner retains external sessions, Lightpanda, WebMCP and engine docs.
Native desktop/app source remains untouched in this worktree. Linux is subsequent
rollout. All heavy work still requires a coordinator resource slot.

## Audit and interface decisions

DesktopBrowserControl already owns tab/generation/document leases, cancellation
and deadlines. DesktopEngine::DispatchTrustedInput checks the target's viewport
center and sends trusted CDP input. Its current selector inspection chooses a first
match, so strict semantic targeting must not silently reuse that behavior.
Captured target identity and renderer/viewport provenance must authorize activation;
a previously returned center coordinate is not sufficient.

ScreenshotHandler already captures viewport PNG/JPEG and refuses full-page input.
Windows and CEF Linux share native/engine-chromium-desktop. Capture sequencing must
reuse its route/lease rather than introduce a parallel CDP ownership path.
The existing persistent gateway keeps unknown completion busy and leaves dialog
recovery reachable. These invariants apply to animated pointer/capture workflows.

The shared/Mac contract owns semantic targeting, pointer easing/path, tap styles,
step capture and output artifacts. Desktop bindings consume generated contracts.
The Linux no-CEF gateway sets browserAvailable:false and cannot advertise live DOM,
input or pixel capture.

Lightpanda must use a separate explicit method inventory and execute-time guard:
the ordinary Playwright backend begins with the full catalogue. Its factory accepts
only an already authorized binding. Allocation must remain outside the adapter:
operator-managed endpoint, fresh owned context/pages, bounded lifetime, teardown.
No model endpoint attach, human profile/cookie import, engine port or AGPL copying.
UOA remains the sole identity authority. Mobile background execution is not implied.

Observations owner approved the isolated lightpanda.ts seam. Workflows owner
approved the seam but does not own general backend allocation; coordinator must
assign allocator ownership. Workflows owns index.ts export coordination.
New observation functions remain excluded from Lightpanda until real backend
conformance demonstrates support. DOM-only status must not invent network/error
counts; unavailable evidence stays explicitly unavailable.

## Requirement checklist

### Windows and Linux CEF

- [ ] Consume the accepted shared contracts in the Windows-first native rollout.
- [ ] Scoped value-free snapshots preserve editor/form omission and ref ownership.
- [ ] Structured extraction is deterministic/bounded with URL, document identity,
      publisher metadata provenance and truncation evidence.
- [ ] Compact diagnostics/readiness report actual state and unavailable evidence.
- [ ] Strict semantic target actions reject missing/ambiguous/stale/disabled/
      occluded targets and revalidate captured identity after scrolling.
- [ ] Activate observed button center under one lease with honest CSS coordinates.
- [ ] Optional S/C pointer motion matches shared easing and coordinate contract.
- [ ] Colored wobble/fade tap circles clean up on stop/navigation/timeout/teardown.
- [ ] Reusable scripts emit step screenshots and supported GIF/video artifacts
      with truthful format/frame timing/size limits.
- [ ] Cancelled/uncertain mutations never replay automatically; late callbacks
      retire ownership without restart.
- [ ] Explicit automation sessions cannot reach human/sibling tabs.
- [ ] HTTP, real MCP and CLI alias forwarding expose the same capability subset.
- [ ] Linux no-CEF refuses new DOM/input/pixel features without advertising them.
- [ ] WebMCP/site declarations stay untrusted and capability-gated; readOnlyHint
      never bypasses mutation authorization.

### Restricted Lightpanda experiment

- [x] External CDP process only; no source copying or native engine port.
- [x] Document no native Windows/Android binary and text-layout image limitation.
- [x] Agree isolated adapter seam with shared observation/workflow owners.
- [ ] Implement explicit conservative method allowlist and execute-time refusal.
- [ ] Assign and integrate trusted operator session allocation/teardown.
- [ ] Admit only owned tabs and proven navigation/DOM/text methods.
- [ ] Exclude canonical screenshots, video/GIF, geometry, visual actionability,
      pointer paths, tap effects and unsupported locator semantics.
- [ ] Check closed/foreign/expired session and tab ownership on every operation.
- [ ] No fallback backend, model endpoint attach or human-session cookie copying.
- [ ] Compare correctness/cost to Chromium on identical bounded deterministic
      tasks; retain failures and scope, without vendor benchmark claims.
- [ ] Exercise external-process CDP before claiming real backend support.

### Verification and release

- [ ] Coordinator allocates resources before heavy build/test/server work.
- [ ] Focused handler/input/MCP tests and required portable checks run on Maxis.
- [ ] Windows build retains pinned sandboxed CEF and matching runtime assets.
- [ ] Launch one exact candidate with dedicated port/disposable profile; stop only
      allocated stale test processes.
- [ ] Real HTTP/MCP/CLI + native UI main/refusal/cancellation/recovery flows.
- [ ] Linux CEF/Wayland and no-CEF bounded checks on separately assigned Fedora
      test checkout; Fedora never develops or hosts normal application services.
- [ ] Base/final screenshots cover only visibly changed states with matching
      viewport/theme; unchanged UI does not need screenshot evidence.
- [ ] Update actual API/functionality docs and platform limitations.
- [ ] Send scoped commit hashes to root; root integrates/releases/cleans up.
- [ ] Verify exact published Windows package against existing Azure signing
      identity and installed user flow before release completion.

## Evidence ledger

| Revision/environment | Flow | Result/artifact |
| --- | --- | --- |
| b6784ff / Maxis / 2026-11-04 | Read-only source/worktree audit | Clean assigned branch; this checklist |
| Assigned Windows native owner | Windows CEF build and real MCP/UI | Not run by this owner |
| Pending assigned checkout | Linux CEF/Wayland and no-CEF | Not run |
| Pending operator allocation | Lightpanda CDP corpus | Not run |

Shared contract c01b2038 was merged as 3c73b227, preserving the draft source.
No build, native launch, functionality/manual acceptance or release is claimed.

## External evidence consulted on 2026-11-04

[Official Lightpanda README](https://github.com/lightpanda-io/browser) documents
Linux/macOS builds, Windows through WSL2, no native Android build, external CDP
and text-only PNG/PDF. Those images are not rendered browser pixels.
[Official Playwright quickstart](https://lightpanda.io/docs/quickstart/installation-and-setup)
uses a separate process and new context via chromium.connectOverCDP.
Protocol connectivity is not proof that all Playwright methods work.
No upstream benchmark claim is used as an acceptance result.

## Worker resource, network and provenance policy

The managed allocator receives an already connected trusted Browser object, never
a URL from a model request. An isolated session requests a fresh context with
service workers blocked and downloads disabled. Shared mode requires the
operator-selected context and owns only pages it creates; it does not enumerate
that context's other pages. The browser process and borrowed context are never
closed as a side effect of session disposal.

Session TTL is 1 second to 1 hour (default 5 minutes). Agent-created tabs are
bounded to 1–16 (default 4). Expiration closes owned resources and rejects further
access. Owner authorization runs before/after asynchronous work; a mutation whose
access ends during dispatch reports uncertainty. Popups are not promoted to owned
tab handles and are closed.

Requested navigation accepts only absolute HTTP(S), rejects URL credentials and
must pass the trusted allowNavigation callback. This is not a network sandbox:
redirects, subresources, WebSockets, service workers in a shared context, DNS and
private-address access require an operator-enforced worker egress boundary.
Likewise, context limits do not impose process CPU/RAM limits; the operator must
bound the external worker process. The API requires that boundary to be explicitly
declared rather than inventing enforcement through CDP.

Lightpanda remains an optional operator-installed external process. Kelpie does
not download, bundle, link, port or copy its AGPL implementation. Capture the
exact executable version/hash, architecture, launch flags, configured boundary
and corpus revision in the acceptance ledger. Transport reuse is not a license
or compatibility claim. Release artifacts must not accidentally include the
external executable.

The initial Lightpanda factory is fail-closed: trusted application code supplies
only candidate methods verified for its actual backend build. Public capabilities
cannot override the adapter's private admission set. The experiment is incomplete
until real navigation/text/extraction corpus results support the admitted profile.
Maxis has no WSL installation; a separately assigned bounded Linux test checkout is
needed for the native Linux binary, without developing or hosting normal services
in Fedora.

## Portable checkpoint evidence, Maxis, 2026-11-04

Candidate source: integration 5db4e2d6 plus this owner's uncommitted worker/WebMCP
tranche, later committed without changing runtime source. Frozen install used
D:/BuildArtifacts/kelpie/capture-desktop-20261104/pnpm-store; no shared writable
cache, WSL install, native build or Computer Use was used.

- Required pnpm lint/build/test passed after corrections. Full test counts:
  shared 120 passed, CLI 632 passed / 64 skipped. Vitest thread/fork maxima were 2.
- Focused managed-session/WebMCP and CLI registry tests passed in the full suite.
- Real sandbox-enabled headless Chromium 151.0.7922.34 ownership corpus passed:
  isolated cookie/localStorage separation; foreign-tab refusal; explicit shared
  cookies while preexisting tabs remain hidden/preserved; expiration denies
  metadata while the borrowed browser remains connected.
- Actual API-enabled WebMCP corpus passed with
  --enable-features=WebMCP,WebMCPTesting. document.modelContext/getTools/executeTool/
  registerTool were present. Discovery/call, hint-independent operator denial,
  toolchange and document invalidation, result bound and timeout uncertainty passed.
  A late invocation retained BUSY until actual reply retired; it was not retried.
- Existing executable read only:
  C:/Users/ondre/AppData/Local/ms-playwright/chromium-1234/chrome-win64/chrome.exe;
  SHA-256 409805A16D6416087E6B2F778DF1CF8F7BBB267D6B99F6B5BB0A618EACE234F2.
- Safe artifacts: D:/BuildArtifacts/kelpie/capture-desktop-20261104/acceptance/
  managed-playwright.json and webmcp-actual-api.json. Required logs: lint.log,
  build.log, test.log in the same task artifacts directory.
- The optional broad CLI tsc --noEmit check exposed existing registry/test typing
  errors outside this tranche. New registry-test literal typings were corrected;
  no unrelated files were changed. Required package build/lint/test are green.

The first real invocation diagnosed an API-version difference, not a failed tool
implementation: Chromium151 takes serialized JSON as its DOMString second
argument. The trusted binding now requires an audited json-string or object
encoding and refuses other choices before invocation. No page/model choice,
automatic call probe or mutation retry is used.
[Exact Chromium151 IDL](https://chromium.googlesource.com/chromium/src/+/refs/tags/151.0.7922.34/third_party/blink/renderer/core/script_tools/model_context.idl)
is the runtime authority; the current WebMCP spec's object argument is a separate
revision.

CLI stdio end-to-end with borrowed endpoint survival, real Lightpanda Linux
navigation/text/extraction/cost and native WebMCP exposure remain pending.
