# Shared browser control v1

The machine-facing core lives at `@unlikeotherai/kelpie-shared/browser-control`.
Kelpie CLI MCP exposes it as `kelpie_browser_control`. Existing native tools
remain extensions. Direct native servers retain their existing catalogues until
their shared protocol adapters are delivered.

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
snapshots are refused. Native observations use a fixed package reader over the
already-admitted `evaluate` route, storing only ephemeral element references on
the page. Native actions verify original object identity and an exact unique
structural selector immediately before the existing native click/type request.
The registry is in the page realm and can be altered by page scripts; it is a correctness guard, not an isolation boundary against a hostile page. The direct native gateway must own references privately. The two native requests are not an atomic browser transaction. Shadow DOM actions
are unsupported on that adapter. No arbitrary model evaluation is introduced.
Mobile handlers select the requested tab before each command because they operate
on the selected renderer.

Navigation uses `tab.goto/back/forward/reload`; observation uses `tab.url/title`,
`tab.screenshot`; page input uses `page.press/scroll`. Mac/iOS/Android key press
remains unsupported. Rich semantic locators, fill/check/select and frame scopes
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
`browserControlInputSchema({methods})`, retaining one authoritative schema while
omitting unsupported variants from a product's model context.

Run ordinary contract/native mock checks with `pnpm test`. Run real headless
conformance separately after installing Chromium and building the package:
`pnpm --filter @unlikeotherai/kelpie-shared test:browser`. This suite exercises
Playwright and a mocked native HTTP-shaped transport backed by real browser pages;
it does not establish physical native-device parity.
