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
  The first corpus checked immediate BUSY; the follow-up below strengthens actual
  completion/abort evidence and never retries a mutation.
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

The later follow-up below completes CLI stdio borrowed-endpoint survival. Real Lightpanda Linux
navigation/text/extraction/cost and native WebMCP exposure remain pending.

## Lifecycle/public-worker follow-up verified on Maxis

Base integration 6cef7fb2 was consumed as merge e9c574d0. Source changes prepared
in this worktree were then checked from merged common base9b939695 (local merge6d74d079):

- WebMCP disposal is rechecked after asynchronous admission and immediately before
  evaluation. An abort rejection marked completionUnknown retains a document-scoped
  fence until trusted exact-page teardown; epochs/URLs do not prove retirement.
- New pages enter owned tracking before later admission. Failed page/context and
  orphan registry cleanup remains retained with automatic backoff; it is not
  swallowed or removed from the resource budget.
- JSON metadata iteration avoids an eager own-key array, checks key length before
  serialization and rejects oversized result strings before UTF-8 allocation.
  Browser API/proxy enumeration itself is not an OS resource sandbox.
- Managed public WebMCP policy takes exact operator webMcpOrigins and audited
  encoding, verifies the origin subset, probes an owned private main-frame CDP world
  and adds canonical methods only for actual eligible pages. The page realm cannot
  self-grant or spoof the API probe.
- A built production CLI stdio corpus covers public observation composition,
  granted/denied WebMCP, page shadows, two managed siblings/popups and human-page
  preservation, isolation, cleanup and borrowed endpoint survival.
- Fedora LP exact-binary/corpus/cost preparation is documented in
  lightpanda-verification.md. No Linux worker or benchmark has run.

Source preparation used no tests, browser, CUA or headed work. The subsequently allocated BACKEND-7 verification is recorded below.

## BACKEND-7 and BACKEND-FINAL-12 evidence, Maxis, 4–5 November 2026

Runtime candidate: merged common9b939695 via6d74d079 plus this scoped follow-up.
The source was frozen during each check; the same runtime source was committed
after verification. The deterministic fixture correction is separate commit
ece3d41a3146db079f9b33e3867e522c26013bf8.

- Required pnpm lint, build and full test passed. Shared139 passed; CLI688 passed
  and1 skipped. Final run used max1 Vitest worker and Node heap2GiB.
- Focused deterministic SSE fixture11 passed. The old test incorrectly expected
  TCP read boundaries to preserve writes; authored LF/CRLF streams now prove
  split UTF-8/data fields and fully coalesced input through the same parser.
  Actual HTTP content, comments, usage, DONE and tool argument fragments remain.
- Lifecycle regressions prove post-admission disposal cannot dispatch; failed
  initial pages/contexts and orphan allocations retain cleanup ownership and
  retry. Hidden initial allocation cleanup also counts against maxSessions.
  Public transports expose only fixed error fields, never cleanup continuations.
- Built production entrypoint node packages/cli/bin/kelpie.js worker mcp passed:
  create/list/control/close; isolated and explicit shared storage; two managed
  shared siblings and their actual popups; foreign-tab and ungranted-origin
  refusal; human pages hidden/preserved; clean shutdown releases owned contexts
  while the borrowed endpoint and human context remain alive.
- Bundled snapshots/extraction/status/readiness passed public facts, value omission,
  publisher provenance and unavailable diagnostic signals. This exercises the
  production fixed-function composition, beyond direct SDK helpers.
- Public WebMCP used the actual Chromium151 API in a private CDP world. The
  fixture's main world successfully replaced document.modelContext with a forged
  catalogue; the public worker still discovered/called the actual registered
  tools. No API polyfill or model-supplied endpoint/origin grant was accepted.
- Actual timeout callback counter remained1 at the mid-flight checkpoint and
  became2 only after its delayed executor. Same-page commands stayed BUSY.
  Chromium rejected the API promise on abort while that executor continued:
  the completion fence correctly remained until exact owned-session teardown.
  No mutation retry occurred. URL/history epochs do not retire this fence.
- Actual standalone managed and API-enabled WebMCP corpora passed. Browser:
  sandbox-enabled headless Chromium151.0.7922.34, existing executable/hash above,
  explicit --enable-features=WebMCP,WebMCPTesting. The audited input encoding is
  json-string for the exact tagged IDL; the current spec's object input differs.
- Package version, public --version and both worker MCP initialize serverInfo
  responses all reported0.1.22. The worker receives the already canonical
  Commander/package version; it adds no central version constant or manifest.
- Safe artifacts under
  D:/BuildArtifacts/kelpie/capture-desktop-20261104/acceptance/backend7:
  worker-stdio.json, managed-playwright.json, webmcp-actual-api.json,
  runtime-source-sha256.json and cli-bundle-sha256.json.
  Final required logs are backend12-lint.log, backend12-build.log and
  backend12-test.log. Prior failing lint/fixture logs remain under backend7-*.
- Initial corrections: explicit callback typing/binding, narrowed capability
  inference, and draining the full actual-reply promise chain in the timeout
  test. The separate SSE correction fixes its transport assumption rather than
  increasing sleeps or waiting for a lucky suite.
- No CUA, headed UI, browser download, native app build or LP worker was used.
  These are machine-interface results, not GTK/Windows/macOS/mobile UI evidence.

Native rollout, native WebMCP grant/API seams, actual Lightpanda1.0.2 corpus/cost,
Linux codecs/GTK/headless/no-CEF/package verification and the integrated published
release remain separate requirements. Linux source now has its own assigned
D:/Worktrees/kelpie/capture-linux-20261104 branch at8423d7df; its adapters are
unbuilt drafts and do not inherit the portable worker acceptance result.

## Lightpanda shared-isolation guard checkpoint (5 November 2026)

The exact 1.0.2 diagnostic limits are recorded in lightpanda-analysis.md and
lightpanda-verification.md. They do not authorize shared storage or a public
reader profile. Both SDK allocation and the production worker factory now refuse
Lightpanda shared sessions with ISOLATION_UNAVAILABLE before allocating or using
a shared context. Tests assert zero borrowed-context access/allocation and
preserve explicit Playwright shared storage and Lightpanda isolated allocation.

Validation on Maxis, based on 635d88ace7f2a7c3f722b4c572fa1e2d3f285945 plus this
scoped draft: cached workspace lint and build passed; all 143 shared tests passed;
CLI: 697 passed and one existing test skipped (58 files). The new allocation
file's three tests passed. Commands used workspace concurrency 1 and test
maxWorkers/minWorkers 1, NODE_OPTIONS=--max-old-space-size=2048, task-owned D:
scratch/caches, with no dependency install, browser, CEF or native app phase.

The busy-host run first found three draft lint errors, which were corrected.
An outer console launcher confinement mismatch was stopped before useful work.
BelowNormal affinity 1 then received only 2.7 CPU seconds in 84 wall seconds.
The coordinator authorized Normal priority while retaining affinity 1 on the
entire workload tree. A harmless five-process parent/direct/cmd/nested/console
probe passed; actual descendant metadata remained affinity 1/Normal. Normal
lint passed in 26.8 seconds and build in 19.3 seconds. The first test attempt was
interrupted when the external metadata monitor raced an exited process; its
logs remain. The repaired monitor allowed the complete full test rerun to finish
at 03:22:09 UTC, with one harmless exited-process metadata race counted.
Free memory was 13.99 GiB at the Normal start and 19.08 GiB after completion.

Evidence is under D:/BuildArtifacts/kelpie/capture-desktop-20261104:
lp-normal-affinity-proof.json; lp-guard-normal-{lint,build}.log;
lp-guard-normal-tests-test.log; lp-guard-normal-tests-phases.jsonl; and
lp-guard-normal-tests-process-proof.json. Earlier lp-guard-* attempts are
retained. No own check process remains. Actual production stdio on Lightpanda,
the corrected diagnostic snapshot assertions, Linux native relink/MCP/CLI,
GTK/Wayland and installed package verification remain unclaimed gates.
