# Native browser gateway bindings

`native/core-mcp` owns the canonical validator, capability projection, reference
ownership, sequential operation state, and MCP translation. One persistent
`KelpieBrowserGatewayRef` serves both `/v1/browser-control` and `/mcp` for a browser.
The final CLI integration forwards canonical requests to that same gateway. Authentication stays
at the existing transport boundary; the gateway never pairs or attaches endpoints.

Include `kelpie/browser_gateway_c_api.h`. Create with JSON containing
`nativeMethods` (callable HTTP kebab-case endpoints), `targeting` (`direct` or
`selected`), `fixedReader`, `allowActions`, and `requireAuthorization`. The latter
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
fixed reader/resolver, never model-authored JavaScript. Bind it to a private
renderer realm where available. The generated scripts retain ephemeral DOM object
identity under a per-gateway random key; the native coordinator privately owns
admitted refs per tab and snapshot. In a page realm this is a correctness guard,
not isolation from hostile page scripts; bindings must report their realm honestly.
Navigation/replaced nodes, another tab's ref and old snapshots refuse. Type appends.
Native screenshots currently support viewport PNG; other request options refuse.
Explicit native timeouts support 1–30,000ms; zero or larger limits refuse.
Selected-tab readers inspect active identity first and never switch in read-only
mode; writable switches require their own authorization step.
Only implemented methods appear in capabilities. Rich locators remain Playwright.

Default MCP tools are `kelpie_browser_control`, `kelpie_extensions` (names), `kelpie_extension_tools` (schemas for up to 20 names), and `kelpie_extension`
`{name,arguments}`. Previously available rich tools remain callable by name and
through the advertised generic extension tool, so embedded AI providers can
reach every admitted feature without requiring dynamic function registration.

CMake explicitly runs `pnpm install --frozen-lockfile`, builds the shared package,
and generates the schema, documentation, fixed reader and Zod parity fixtures in
the build directory. Native builds require Node 20+ and pnpm; generated assets
are never committed. A portable source lock serializes dependency/build generation across concurrent
Android ABI configurations. CMake regenerates when authoritative sources or lockfiles
change. CI/native release jobs must install those tools before configuring CMake.
Run `test_browser_gateway` via CTest for schema defaults/bounds, malformed requests,
authorization, cancellation, cross-tab refs, no retries and binary MCP output.

## Apple bindings

macOS 0.1.29/build23 and iOS 0.1.14/build14 expose canonical requests at
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

Apple `/mcp` accepts an authenticated MCP initialize/list/call handshake. Accepted
notifications return HTTP 202 with an empty body; canonical operation failures
remain HTTP 200 envelopes so clients preserve `mayHaveCompleted`. Authenticated
GET returns 405; unsupported explicit `MCP-Protocol-Version` headers return 400.
The native transport rejects browser-supplied Origin headers, including `null`,
after existing bearer admission.
