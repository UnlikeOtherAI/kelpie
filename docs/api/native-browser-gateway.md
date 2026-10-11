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

Run `node tests/native/run-control-acceptance.mjs <absolute-native-executable>`
on the target host for the real MCP SDK handshake and canonical browser journey,
including uncertain renderer timeout, BUSY refusal, late completion and recovery.
Pass `--fallback` for the no-CEF Linux executable; it instead verifies truthful
DOM refusal. Each run owns its temporary profile, token and exact process.
