# Shared browser control v1

The machine-facing core lives at `@unlikeotherai/kelpie-shared/browser-control`.
Native HTTP `/v1/browser-control`, direct MCP, and CLI MCP expose the same native-owned
gateway. The default MCP catalog contains `kelpie_browser_control`, extension name
discovery, schema discovery, and `kelpie_extension` invocation. Rich product tools
remain reachable through that advertised extension doorway and their existing names.
The CLI forwards canonical requests; it does not own a second reference registry.

For example, `kelpie --device <id> browser-control '{"version":1,"method":"tabs.list"}'`.
The same versioned JSON works through SDK, HTTP and MCP. Existing rich CLI commands
remain available.

The tool accepts `{device?, request:{version:1, method, tabId?, params}}`.
Call `documentation` once for method details, then `capabilities` for the exact
methods available on the selected device. It never pairs implicitly. Device
capabilities and existing authentication remain authoritative. Read and action
requests use one queue per exact device socket and local launch identity.

Start with `tabs.list` or `tabs.new {url?}`. Choose `tabId` explicitly for each
page operation. `tabs.select`, when supported, chooses the active tab.
`tab.snapshot {maxElements?,maxChars?}` returns bounded URL/title, compact text,
and `{ref,role,name}` elements; it never reads form-control values. Input values,
textarea defaults and contenteditable text are excluded. Page content remains
untrusted and product disclosure/scrubbing policies still apply. The default
limits are 200 elements and 16,000 text characters, with bounded metadata.

`tab.click {ref}` and `tab.type {ref,text}` act only on the latest observed
reference in that tab. Type appends. Observe again after every mutation or
snapshot. Navigation, detached/replaced elements, another tab's refs and previous
snapshots are refused. Native snapshots use the generated fixed reader, with an
opaque generation per gateway. Captured DOM references live in the renderer realm;
CEF uses a private isolated world. Android's WebView uses its page realm, so its
registry is a correctness guard and not isolation against hostile page scripts.
Native click/type are one fixed operation on the captured object, never a selector
re-query: click performs DOM activation, and type appends through the native value
setter and dispatches an input event (or appends a text node in contenteditable).
These events are synthetic. Rich Kelpie input extensions retain their platform
event guarantees; Playwright retains its native input behavior. Focus handlers can
run synchronously, so object identity is checked again after focus; refusal after
focus reports uncertainty. Shadow DOM actions are unsupported on native.
No arbitrary model evaluation is introduced. Selected-renderer bindings inspect
the actual current tab and authorize a switch only when needed; read-only sessions
refuse other tabs without switching.

Navigation uses `tab.goto/back/forward/reload`; observation uses `tab.url/title`,
`tab.screenshot`; page input uses `page.press/scroll`. Key press support depends on actual advertised platform capabilities. Rich semantic locators, fill/check/select and frame scopes
are implemented by Playwright only; the native adapter does not advertise them.
Native extensions keep their own platform/input guarantees.

Playwright wraps only session-authorized pages supplied by its binding; it never
launches or attaches to a model-provided endpoint. Semantic locator actions use
Playwright's strict single-match behavior, default 10-second waits and a maximum
120-second explicit timeout. `fill` replaces, `type`/`pressSequentially` append.

Requests are strict Zod v1 contracts. Responses are `{version:1,ok:true,value}` or
`{version:1,ok:false,error:{code,message,mayHaveCompleted}}`. An uncertain mutation
is never retried automatically. Read and reconcile after `mayHaveCompleted:true`.
Generic backend errors are replaced with secret-safe text; products can preserve
durable fatal fences through `isFatalError` and apply `authorize` and `scrub`.
Screenshots use one wire image value and one MCP image block, never base64 text.

The async JavaScript SDK follows the supported Codex browser subset:
`browser.tabs.list/new/get/select`, tab navigation, `tab.click(ref)`,
`tab.typeText(ref,text)`, `getAXState/getScreenshot`, and `tab.playwright` locator
builders. `screenshot()` returns `Uint8Array`; the wire carries a typed image.
Unsupported Codex features are not emulated. Method schemas can be generated from
`browserControlInputSchema({methods,compact:true})`, retaining one authoritative
method enum with open parameter contents for compact model context. The canonical
request validator remains strict and validates every call before dispatch. Omit
`compact` for full typed method schemas. `tab.pressKey(null,key)` and convenience
`tab.pressKey(key)` target the page; non-null ref key presses and focused
`typeText(null,text)` refuse explicitly in this supported subset.

Run ordinary contract/native mock checks with `pnpm test`. Run real headless
conformance separately after installing Chromium and building the package:
`pnpm --filter @unlikeotherai/kelpie-shared test:browser`. This suite exercises
Playwright and a mocked native HTTP-shaped transport backed by real browser pages;
it does not establish physical native-device parity.

Rich extension schemas come from `packages/shared/src/extension-tools.ts` and
`extension-ai-tools.ts`, shared with the CLI. Native generation projects the
forwarded body: device selection stays on the CLI host, native window/generation
routing remains optional, and screenshots retain the CLI's viewport default.
Native endpoint configuration does not accept `apiKeyEnv`; that field is resolved
by the CLI host before its authenticated HTTP request. Existing device endpoint
configuration retains its separate protected key path. Device handlers still
validate semantic constraints such as partition identities and endpoint URLs.
Generation refuses unsupported JSON Schema keywords; native tests cover every
registered extension and forwarded argument shape. `get-links` is a read-only
macOS WebKit/Chromium extension returning up to 200 href/text pairs.

The Linux fallback advertises only its actual metadata/legacy capabilities. Its
MCP HTTP route uses the desktop local-client, bearer, content/accept and protocol
version guards. Unsupported SSE GET returns 405; accepted notifications return
202 with an empty body. It does not advertise live browser observations.
