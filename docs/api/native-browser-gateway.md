# Native browser gateway bindings

`native/core-mcp` owns the canonical validator, capability projection, reference
ownership, sequential operation state, and MCP translation. One persistent
`KelpieBrowserGatewayRef` serves both `/v1/browser-control` and `/mcp` for a browser.
The CLI forwards canonical requests to that same gateway. Authentication stays
at the existing transport boundary; the gateway never pairs or attaches endpoints.

Include `kelpie/browser_gateway_c_api.h`. Create with JSON containing
`nativeMethods` (callable HTTP kebab-case endpoints), `targeting` (`direct` or
`selected`), `browserAvailable` (default true), `fixedReader`, `allowActions`, and `requireAuthorization`. The latter
two default true. Pass existing extension descriptors as
`{name,method,description,inputSchema,mutates}`. Include only admitted functions;
read-only AI sessions must disable actions and further restrict visible tabs.
Native registry descriptors include `method`, `inputSchema` and structural
`mutates` from the shared C++ extension catalogue; reuse those descriptors rather
than copying schemas into Swift or Kotlin.

Serialize the entire transaction, including policy checks. `begin` accepts a
canonical request; `begin_mcp` accepts JSON-RPC. They return a step:

- `authorize`: inspect `request` and structural `mutates` using existing site,
  tab visibility and user-action policy; advance `{success:true}` only if admitted.
- `dispatch`: invoke the named native handler with `params` exactly once, then
  advance its existing `{success:true,...}` result. Failed, lost or cancelled
  dispatched mutations retain `mayHaveCompleted:true` and must never retry.
- `complete`: return `response` to the caller. MCP responses already contain the
  JSON-RPC envelope and one binary image content block without base64 text.

`next` reads the pending step; `advance` consumes its result. `cancel` is mandatory
on renderer timeout/cancellation. A concurrent begin returns BUSY without replacing
the active transaction. The C ABI request JSON limit is 4MiB, sufficient for maximum escaped core typing
text; renderer response JSON is bounded at 32MiB. Transport listeners may apply
their own documented limits before admission. Free every returned C string with `kelpie_mcp_free_string`.
Do not destroy a gateway while a renderer callback is pending.
Call `kelpie_browser_gateway_invalidate_refs` for legacy mutations/navigation
outside the canonical gateway; pass null to invalidate all tabs. Rich extension
mutations dispatched inside the gateway also invalidate their target refs.

The special internal `browser-control-evaluate` dispatch executes a generated
fixed reader or atomic captured-node action, never model-authored JavaScript. Bind it to a private
renderer realm where available. The generated scripts retain ephemeral DOM object
identity under a per-gateway random key; the native coordinator privately owns
admitted refs per tab and snapshot. In a page realm this is a correctness guard,
not isolation from hostile page scripts; bindings must report their realm honestly.
The ephemeral renderer registry also clears on pagehide/popstate/hashchange, so a BFCache restoration cannot revive an observed handle. Navigation/replaced nodes, another tab's ref and old snapshots refuse. `tab.click` performs synthetic DOM activation on the captured object; `tab.type` appends through native value setters and an input event on text inputs/textarea, or text-node append in contenteditable. Number/file/date/checkbox inputs refuse typing before focus. After focus, eligibility and connection are checked again because page handlers can mutate them; refusal then reports uncertainty. Rich native input extensions retain their event guarantees.
Native screenshots currently support viewport PNG; other request options refuse.
Explicit native timeouts support 1–30,000ms; zero or larger limits refuse.
Selected-tab readers inspect active identity first and never switch in read-only
mode; writable switches require their own authorization step.
Only implemented methods appear in capabilities. Rich locators remain Playwright.

Default MCP tools are `kelpie_browser_control`, `kelpie_extensions` (names), `kelpie_extension_tools` (schemas for up to 20 names), and `kelpie_extension`
`{name,arguments}`. Previously available rich tools remain callable by name and
through the advertised generic extension tool, so embedded AI providers can
reach every admitted feature without requiring dynamic function registration.

CMake explicitly runs `pnpm install --frozen-lockfile`, cleans and builds the shared package,
and generates the schema, documentation, fixed reader and Zod parity fixtures in
the build directory. Native builds require Node 20+ and pnpm; generated assets
are never committed. A portable source lock serializes dependency/build generation across concurrent
Android ABI configurations. CMake regenerates when authoritative sources or lockfiles
change. Generated UTF-8 byte arrays avoid compiler string-literal limits while preserving identical assets. CI/native release jobs must install those tools before configuring CMake.
Run `test_browser_gateway` via CTest for schema defaults/bounds, malformed requests,
authorization, cancellation, cross-tab refs, no retries and binary MCP output.

The Linux no-CEF fallback also serves authenticated canonical HTTP and compact MCP through this coordinator. Its core advertises only documentation/capabilities; existing metadata, navigation stub, bookmarks/history and diagnostics remain discoverable extensions. It does not advertise DOM observations or browser input.

Windows one-shot inference page context now reads the bounded value-free common snapshot through the same native gateway. Its existing page_text/dom/accessibility labels select that shared representation; they do not inject raw DOM values. Windows still refuses agent execution and has no tool loop. Linux has no embedded inference tool loop to migrate. Native local GGUF also remains text/page-context only. Desktop navigation/title callbacks queue reference invalidation without taking the transaction mutex on the renderer thread; the next gateway step drains it.

## Apple bindings

macOS 0.1.30/build24 and iOS 0.1.15/build15 expose canonical requests at
`POST /v1/browser-control` and the compact four-tool catalog at `POST /mcp`.
Both routes pass the existing pairing bearer/header gates. Canonical refusal and
unknown outcomes retain HTTP200 with the versioned envelope; malformed JSON and
authentication failures retain HTTP4xx. The generated fixed evaluator has no
public HTTP route.

The shared Swift coordinator is compiled into both apps. WebKit uses the named
`KelpieBrowserControl` content world. macOS Chromium uses the same existing
bounded native CDP transport for main-frame discovery, an isolated world without
universal access, and fixed evaluation. Page scripts cannot replace this world's
reference registry. CEF rechecks renderer visibility between asynchronous frame,
world and fixed-evaluation commands. Canonical clicks activate the observed DOM object and type
appends with input/change events; rich extensions retain native input semantics.
Navigation, renderer changes and legacy/rich mutations invalidate references.
Chromium exposes one `chromium` handle and omits unsupported tab lifecycle methods.
WebKit preserves explicit native tab/window ownership. iOS dispatch rechecks the
selected WebView identity after asynchronous inspection; it never acts on a tab
whose selected renderer changed. External-display WebKit exposes its own `external`
handle through that display's separately authenticated server.

OpenAI-compatible inference and the Mac local GGUF harness use a fresh policy-bound
compact catalog per run. The remote lane retains its existing narrower admission;
the local read-only lane retains console, errors, network, cookies, storage,
links, DOM, element/form and accessibility reads through shared rich extensions.
Local screenshot discovery requires the loaded model's vision capability; one
image reaches inference separately from the bounded text, without base64 text.
Only previously admitted product features appear;
`allowActions:false` removes common and extension mutations. Both Apple agents
stay in the visible pinned tab and refuse model-selected tab/window changes or
later UI tab changes. iOS local GGUF inference remains a single-shot lane and uses
the bounded common snapshot for optional page context. Ambiguous mutations stop the
AI turn instead of feeding an error into another action attempt. A renderer deadline returns uncertainty and keeps the lease exclusive until its
pending callback retires; later explicit requests can reconcile or continue. Late
callbacks cannot advance the cancelled coordinator or replay the command.

Mac candidate signing uses Xcode's real selected identity for staged CEF bundles
and preserves helper entitlements; no script introduces ad-hoc signatures. Local
Apple Development signing demonstrates a development candidate only. The current
repository's release workflow does not establish Developer ID notarization, and
iOS simulator artifacts do not establish physical-device signing or an IPA release.
Binding regressions live in `BrowserControlGatewayTests` (compiled on both Apple
targets), alongside the model-loop fixtures and shared native CTest coverage.
`RealWebKitBrowserControlTests` runs the production Swift router, native C ABI,
private reader/actions and screenshot against a non-persistent, XCTest-owned
WebView/window on both platforms, without pairing or restoring user data.

Apple `/mcp` accepts an authenticated MCP initialize/list/call handshake. Accepted
notifications return HTTP 202 with an empty body; canonical operation failures
remain HTTP 200 envelopes so clients preserve `mayHaveCompleted`. Authenticated
GET returns 405; unsupported explicit `MCP-Protocol-Version` headers return 400.
The native transport rejects browser-supplied Origin headers, including `null`,
after existing bearer admission.

The durable Apple candidate journey is `scripts/native/apple-browser-control-journey.mjs`.
Launch the exact development candidate on a dedicated port (Mac `--port 18520`),
then run `node scripts/native/apple-browser-control-journey.mjs http://127.0.0.1:18520 macos`
or launch the Debug simulator with `--port 18530` and use that port plus `ios`.
The journey always requests a new disposable one-session pairing; approve its
visible native request. The fixture uses a standard MCP SDK client and exercises private-world
spoof resistance, editable-value omission, atomic observed actions, append, stale
DOM replacement, screenshot presentation, and both Mac renderer profiles. Pairing
tokens stay in process memory; the fixture always creates its own grant and
asserts successful revocation and refusal of the old bearer. Fixture tabs close afterward.

Long-running rich inference/recording extensions use a dedicated coordinator,
selected by the authoritative extension descriptor, so the persistent direct
coordinator remains available for other explicit requests. Inference delegates
admission to its inner browser requests;
it does not hold the browser lease across model inference. Its existing model
and run deadlines remain authoritative, avoiding both self-blocked tool loops
and a detached outer timeout while an AI turn continues to act.

Apple WebKit retains the named private content world for the binding lifetime so
observed DOM objects survive between snapshot and action. The iOS callback bridge
awaits the actual WebKit result. Completed reads are discarded when their renderer
or an agent's pinned visible tab changes during dispatch; dispatched mutations
retain uncertainty. Isolated real-WebKit fixtures exercise this boundary on macOS
and the iOS simulator, including captured-node activation, append, replacement
refusal and single-image screenshot output.
Run `node tests/native/run-control-acceptance.mjs <absolute-native-executable>`
on the target host for the real MCP SDK handshake and canonical browser journey,
including uncertain renderer timeout, BUSY refusal, late completion and recovery.
On Windows the SDK journey also checks nested common inference page context and
cancellation through an owned local mock endpoint. Pass `--fallback` for the no-CEF Linux executable; it instead verifies truthful
DOM refusal. Each run owns its temporary profile, token and exact process.

Common Apple WK/CDP operations retain the pending lease until their actual result
or confirmed renderer close. Legacy inner timeout and CDP agent-detach callbacks
do not retire a common gesture. A real WebKit cancellation fixture holds a 9.5s
page handler past the former 8s inner deadline; CDP callback fixtures cover the
former 5s deadline, detach, late result and confirmed close separately.

Only POST `/v1/pair` may enter pairing without a bearer. DELETE requires the
existing bearer, revokes that client, and immediately rejects its old token on
both Apple transports; the candidate journey uses this authenticated cleanup.

## Per-tab conversation grounding

The tab chat integration keeps caller history in full and captures one owned renderer for model grounding. Android and Apple preload paths invoke a read-only shared `tab.snapshot` transaction, bounded to 12,000 characters and 200 elements, through the existing renderer lease. Background WebKit/WebView observations do not switch the visible tab. Renderer identity and ownership are checked before and after evaluation; inactive Chromium targets are refused. Rich HTTP extraction remains an explicit extension/API, rather than a second default model observation path. Windows checks the captured tab generation before and after the common snapshot and adds evidence to the current user turn while retaining earlier conversation turns.

Read-only, one-shot page observers execute the fixed reader without remembering DOM targets or installing reference invalidation listeners. Their snapshot references cannot authorize actions; persistent action-enabled gateways remain the sole owner of actionable native references.
The macOS native single-shot harness also obtains its initial public URL/title metadata from its admitted common gateway. It has no separate page-summary JavaScript collector or silent empty-summary fallback.

Desktop renderer retirement keeps native dialog observation and accept/dismiss controls reachable while a dialog-blocked renderer command remains outstanding. These recovery handlers use the existing native dialog state/callback; other browser actions and common observations stay busy until the renderer reply retires.
