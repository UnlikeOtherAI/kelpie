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
the active transaction. Free every returned C string with `kelpie_mcp_free_string`.
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
