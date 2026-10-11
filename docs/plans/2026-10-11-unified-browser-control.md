# Unified browser control

## Goal and delivery

Nessie, SalesNerd and Kelpie use one versioned browser command contract and JavaScript client. The public client follows the supported Codex browser shape (`browser.tabs`, `tab.goto`, `tab.playwright.getByRole(...).click`). Browserbase and local Playwright sessions pass through the same proxy implementation. Kelpie-specific features remain discoverable extensions. This is a machine-facing contract; its doorways are Kelpie MCP/CLI, Nessie's existing browser tools and Computers assignments, and SalesNerd's existing browser assistant and research pane.

The contract lives in `@unlikeotherai/kelpie-shared/browser-control`; it contains no CLI startup, discovery, credentials or application state. The existing shared npm release owns its version. Both products pin that published version. The CLI adapter uses the same contract directly. There is one implementation, not copied source in three repositories.

## Contract

A request is `{version: 1, method, tabId?, params}`. Browser/session selection is made by the caller's already-authorized transport, never by a model-supplied CDP URL or credential. `BrowserControlRequestSchema` validates every command. `createBrowserControlProxy(backend, {authorize?,scrub?,isFatalError?})` serializes commands, checks authorization on every call and returns `{version:1, ok:true, value}` or `{version:1, ok:false, error:{code,message,mayHaveCompleted}}`. A lost reply after a mutation is an unknown outcome, never permission to repeat it.

`createBrowserClient(transport)` exposes `tabs.list/new/get/select`, tab navigation/back/forward/reload/close, url/title, screenshots, AX/DOM snapshots and `tab.playwright` locators. A locator is serializable data: role/name, label, text, placeholder, test ID or CSS, chained descendants, frame scope, nth and text filtering. Native page code and credentials are never model arguments. `fill` replaces; `type` appends; `press` names a key chord; check/uncheck/selectOption are explicit state changes. Locators re-resolve before dispatch; ambiguous matches fail. Waits retry reads only. Arbitrary evaluation is not part of this core: Kelpie's existing evaluation remains an explicit extension.

Core methods: `tabs.list`, `tabs.new`, `tabs.close`, `tabs.select`; `tab.goto`, `tab.back`, `tab.forward`, `tab.reload`, `tab.url`, `tab.title`, `tab.snapshot`, `tab.screenshot`; `locator.click`, `locator.dblclick`, `locator.fill`, `locator.type`, `locator.press`, `locator.check`, `locator.uncheck`, `locator.selectOption`, `locator.innerText`, `locator.textContent`, `locator.getAttribute`, `locator.count`, `locator.isVisible`, `locator.isEnabled`, `locator.waitFor`; `page.press`, `page.scroll`; `capabilities`, `documentation`.

Snapshots share the same compact text format and omit password/input values. Screenshots travel as a single typed image result. Product scrubbing and attachment policies still run. Capabilities list the exact implemented methods and extensions; unsupported operations return a typed refusal, never a guessed substitute. Capability availability does not grant permission.

## Backends and product boundaries

- Playwright backend wraps an already-authorized page/context. It does not launch or attach to arbitrary URLs itself. Browserbase session allocation, persistence and release remain with their existing owner, including SalesNerd's Ledger accounting.
- Kelpie CLI backend calls the existing authenticated native routes and uses the fixed shared value-free reader only when `evaluate` is admitted. Original DOM object identity is checked before an exact structural selector reaches native click/type; this two-request boundary is not atomic. Native rich locators remain unsupported. Mobile selected-renderer handlers explicitly select the requested tab before commands. Direct native MCP/HTTP core adapters across all five apps are a separate required delivery tranche.
- Nessie retains signed executor commands, team/owner access, revision fences, origin approval, secure entry and screenshot disclosure. The existing cloud-browser page channel binds the proxy to the owned target. Connected Chrome remains disabled until its existing disclosure gate is actually implemented.
- SalesNerd retains its owner/team session capability, allowed sites, user handover and research scope. Browser actions pass through that policy before the common control proxy. Product research tools such as extract/note/done remain above the browser core.
- Native app/OS control is a separate adapter family; browser standardization does not grant desktop access.

## Verification

### Native delivery scope

Every native app must serve the common contract directly through authenticated
`/v1/browser-control` and its MCP surface. The CLI forwards that contract to the
native owner; it must not maintain a second reference store. The native gateway
and generated contract data are shared, with platform bindings for renderer
dispatch. Existing richer features remain discoverable extensions.

| Component | Required integration | Acceptance evidence |
| --- | --- | --- |
| Shared native libraries | Validator, gateway, capability schema and on-demand documentation | Contract conformance and refusal/uncertain-outcome tests |
| macOS | Both renderers, HTTP/MCP and built-in AI tools | Swift lint/build, installed release and direct control journey |
| iOS | HTTP/MCP and built-in AI tools | Swift lint/build and simulator journey; preserve visible-tab restrictions |
| Android | HTTP/MCP and built-in AI tools | Gradle build/lint and emulator/device journey matching iOS |
| Windows | Chromium HTTP/MCP and built-in AI tools | Native build/tests and direct control journey |
| Linux | Chromium HTTP/MCP and built-in AI tools | Native build/tests and headless control journey |
| CLI and shared SDK | Canonical transport, compact model catalog and extension discovery | Package tests, real MCP client, published install verification |

Read-only AI requests must remain read-only, and platform capability differences
must be advertised accurately. A successful TypeScript adapter test does not
establish native execution. Track build, simulator, installed-app and physical
device evidence separately in the final delivery report.

The separate headless `test:browser` suite runs navigation, append, stale and replaced references, tab scoping, value-free bounds and screenshot scenarios against Playwright and a native-shaped mocked transport backed by Chromium. Playwright additionally verifies role/label lookup, fill versus append, checkbox/select, strict match and timeout. This does not establish physical-device native parity. Contract tests cover invalid commands, prototype/unknown fields, authorization, queue recovery, unknown mutation outcomes and capability refusal. Product tests cover real dispatch through the proxy plus their existing private-session and policy gates. Browser UI checks stay outside Nessie CI. Verify published package exports from a clean consumer before product release.

Measure instruction size, response size, tool round trips and task completion on the same journeys. No token-saving percentage is claimed without a paired measurement.
