# Desktop capture and restricted worker backend

Owner: desktop-backend. Audited base: b6784ff723b27da4096fdd8d9227f2a00dfc9084.
Branch: codex/capture-desktop-20261104.
Worktree: D:/Worktrees/kelpie/capture-desktop-20261104 on Maxis.
This checklist records planned work and evidence, not completed platform support.

## Mac-first gate

Windows/Linux native implementation, builds, launches, installation and release
wait for the coordinator's Mac-accepted integration revision and resource slot.
No desktop runtime changes were made during this audit.

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

- [ ] Receive Mac-accepted integration base and consume shared generated contracts.
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
| Pending Mac acceptance | Windows CEF build and real MCP/UI | Not run |
| Pending assigned checkout | Linux CEF/Wayland and no-CEF | Not run |
| Pending operator allocation | Lightpanda CDP corpus | Not run |

No build, native launch, functionality/manual acceptance or release is claimed.

## External evidence consulted on 2026-11-04

[Official Lightpanda README](https://github.com/lightpanda-io/browser) documents
Linux/macOS builds, Windows through WSL2, no native Android build, external CDP
and text-only PNG/PDF. Those images are not rendered browser pixels.
[Official Playwright quickstart](https://lightpanda.io/docs/quickstart/installation-and-setup)
uses a separate process and new context via chromium.connectOverCDP.
Protocol connectivity is not proof that all Playwright methods work.
No upstream benchmark claim is used as an acceptance result.
