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
methods available on the selected device. The CLI transport authorizes an existing
same-account UOA session automatically; callers without account authorization
must pair explicitly. See [account pairing](account-pairing.md). Device
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

Desktop CDP timeouts retain execution ownership until the renderer's late reply or
confirmed tab teardown. New browser commands refuse `BUSY` while completion is
unknown; cancellation and tab/browser close remain reachable. A callback retires
ownership automatically, without requiring a restart. MCP inference/recording
uses an admitted outer request separate from the persistent browser gateway, so
its existing nested browser observations can acquire the browser lease.

Windows chrome appearance sampling uses a separate fixed internal CDP observation
(frame/layout metadata and rendered pixels), without page JavaScript or ref writes.
Its late callback remains owned but does not fence public browser commands. This
is unavailable through model inputs: public evaluation, screenshot and canonical
snapshot requests keep the completion fence described above.

Value-free snapshots include visible named SVG graphics as `img` elements, using
ARIA names before a direct SVG `title`; unnamed and hidden graphics are omitted.
This preserves accessible logo evidence for existing page-grounded conversations.

The value-free fixed snapshot reader also omits text reached through accessible-name references when the referenced label inherits content editability from an ancestor.

Snapshot `truncated` also reports public text shortened by per-node or accessible-name bounds. Deliberately omitted form/editor values do not set this flag.

## Scoped observations and deterministic extraction

Snapshots prioritize controls/links, headings, landmarks, then prose, preserving source
order within each class. `prioritize:false` restores document order. Optional
`scope:"main"` must match exactly one element and narrows the authorized document;
missing or ambiguous scope refuses, as does a bounded search that cannot prove
uniqueness. The scope root and its descendants are observed. Supported `:scope`
forms are the root itself, one simple descendant, or one simple direct-child selector;
more complex `:scope` expressions and escaped selectors refuse explicitly. Use
attribute selectors with literal IDs when CSS escapes would otherwise be needed. Other CSS matching and layout
remain browser-engine operations; the work bounds govern JavaScript traversal,
materialization, copied text, and ancestor/style inspection, not engine-internal cost.
Traversal/output bounds, value exclusion, and fresh-reference semantics still apply.

`tab.extract {scope?,fields,metadata?,maxChars?}` performs fixed, deterministic reads.
Each field is `{name,selector,source?,multiple?,fields?}`. Ordinary selectors query
descendants; the exact `:scope` selector (case insensitive) explicitly selects the
current content/record root. Source defaults to `text`;
only `text`, `href`, `src`, and `datetime` are accepted. Nested `fields` maps repeated
records relative to each matching parent. Three mapping levels, 32 top-level fields,
16 fields per nested mapping, 100 total records, and 512 nested field evaluations
bound the operation. The default 8,000-character public-value budget can be set from
256 to 16,000; each individual value is capped at 2,048 characters. Form controls,
editable subtrees, hidden content, scripts, styles, and templates are excluded.

Results contain `url`, `documentRevision:{availability:"unavailable"}`, `fields`,
`metadata`, and `truncated`. Each field reports `name,status,values,provenance`;
nested mappings additionally return `records`, an ordered array of field arrays.
Single-valued fields refuse arbitrary first-match selection: zero matches means
`missing`, several means `ambiguous`, both with empty values. Queries sample at most
5,000 DOM nodes per traversal, with a shared 20,000-unit node/ancestor-style work budget and depth 40. When traversal bounds prevent proving a single result or absence, status is
`incomplete`; provenance sets `matchesLimited:true`. Other limits set `truncated`.
The source document URL and each mapping's selector/source/match count preserve
provenance; no immutable DOM revision is invented.

`metadata:true` explicitly requests document-level publisher claims independently of
the optional content scope. Allowlisted metadata covers canonical URL, description,
author, publisher, publication time, and title. JSON-LD processing reads only eight
`application/ld+json` scripts, at most 32,768 UTF-16 code units each and 65,536 total; malformed JSON is
ignored. At most 32 objects per script, including top-level arrays and `@graph`, expose
only `@type`, `name`, `headline`, `datePublished`, `dateModified`, `url`, and bounded
author/publisher names. Raw JSON, arbitrary object properties, script text, and
article bodies are never returned. Every metadata item includes its selector,
attribute/JSON path, `provenanceComplete`, and `authority:"publisher-claim"`.
A complete source scan also includes a zero-based `index` among all raw matching
source nodes, including private, empty, or malformed records that are omitted from output. An incomplete scan omits that index and never invents an exact CSS path.
These are untrusted claims, never identity, verified facts, or instructions.

`tab.status {}` reports current URL/title, document state, visibility, viewport,
and visible dialog, busy-region, and aria-invalid counts. One traversal inspects at
most 5,000 DOM nodes; partial counts are lower bounds and disclose `truncated`. Network and runtime-error evidence explicitly
return `{availability:"unavailable"}`; absence of evidence is never zero errors or
network health. No observer is installed.

`tab.ready {state?: "interactive"|"complete",selector?}` checks an immediate predicate.
The default is interactive; an optional selector must have exactly one visible match
intersecting the viewport. Ancestor opacity zero, hidden/collapsed visibility, and
non-rendered boxes refuse visibility. The ready rectangle also intersects ancestor
overflow clipping rectangles. Snapshot/extraction may still observe rendered
offscreen content. A search that cannot prove uniqueness returns `incomplete:true`
and `ready:false`; `matchesLimited:true` marks a lower-bound match count.
The result includes `ready,documentState,requestedState` and optional
`selector,matches,visible`. It never waits, accepts no timeout, and does not claim SPA
completion, network idle, or task success. Bounded workflow polling owns any deadline.
All these operations remain read-only, authorized and scrubbed through the existing
gateway. A native device advertises them only with its fixed-reader capability.

Native workflow bindings use generated shared assets through
`kelpie_browser_validate_script(script_json)` for strict schema validation/defaults and
`kelpie_browser_script_target_expression(options_json)` for a fixed target expression.
The latter accepts `{target,key,token?,dispatch?,edit?,observe?,policy?}` with mutually exclusive
operations. Optional private `policy:{refuseSensitive:boolean}` is the seventh fixed
resolver argument; omitted policy preserves the six-argument behavior. Every explicit
result carries token-latched `sensitive:boolean` and `sensitivityKnown:boolean`,
including failed checks. Only false sensitivity with known:true proves a
nonsensitive target; missing token/new realm yields known:false. True sensitivity
always protects. Old/malformed results missing the known flag are conservative
after an attempted target evaluation. Capture
runners set the policy and consume classification before post-evaluation guards,
register edit text, and latch media discard. See [late sensitivity](../plans/browser-automation-capture/late-sensitive-target.md). These internal APIs do not resolve host secrets or authorize a workflow;
the runner must enforce session ownership, binding and sensitivity/capture policy.
Generated Zod/native parity fixtures include duplicate capture-format refusals.

For trusted native get-script-artifact execute failures, direct and generic MCP
preserve only ARTIFACT_NOT_READY (authorized active run) and ARTIFACT_NOT_FOUND
(opaque absent/foreign run), with fixed safe gateway messages. Native response
messages/data are never forwarded on failure; unrelated codes remain
COMMAND_FAILED. Existing uncertainty is retained. Platform routes still validate
the request and owner before deciding active/terminal availability.

## Typed WebMCP seam

The canonical request union includes `tab.webmcp.discover {origin,maxTools?,maxChars?}`
and `tab.webmcp.call {origin,ref,input?,timeoutMs?}`. Discovery is read-only; every call
is treated as mutating regardless of page-provided annotations. Origin is the requested
exact HTTP(S) origin and never a permission grant. Tool definitions and results remain
untrusted page evidence. Unknown fields and non-canonical origins refuse in shared
validation; invocation inputs must pass the shared bounded plain-JSON validator.

These typed variants alone provide no runtime support. Generic Playwright and default
native gateways do not advertise or execute them. A managed/native binding must first
supply an operator session/origin/document-generation grant and probe the actual API;
its trusted input encoding is never a model parameter. Native support must preserve
shared semantic validators beyond JSON Schema shape before advertising these methods.
The managed runtime/config and native launch wiring are separate integration dependencies.
Never retry an invocation with an uncertain outcome.
