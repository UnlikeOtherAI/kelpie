# Operator-managed external workers

`kelpie worker mcp --config <operator-json>` starts one stdio MCP process for an
explicitly configured external Playwright/CDP or restricted Lightpanda worker.
Native Kelpie commands continue to use authenticated HTTP/JSON under `/v1/`.
This command does not replace the native app or introduce a second script runtime.

## Startup configuration

The operator sets the endpoint in an environment variable and supplies a JSON file:

```json
{
  "version": 1,
  "backend": "playwright",
  "endpointEnv": "KELPIE_WORKER_CDP",
  "allowedOrigins": ["https://example.com"],
  "networkBoundary": "operator-enforced",
  "maxSessions": 4,
  "maxTabs": 4,
  "maxTtlMs": 300000
}
```

Launch with `kelpie worker mcp --config C:/path/to/worker.json`.
The referenced endpoint must be an absolute WS/WSS/HTTP/HTTPS URL without embedded
username/password or fragments. Endpoint credentials belong in the protected
operator environment, never model tool arguments or logs. Standard output is the
MCP protocol; startup and cleanup failures use fixed messages on standard error.

The operator must enforce worker process CPU/RAM, network egress and lifetime
boundaries. The CLI validates requested HTTP(S) navigation origins and rejects URL
credentials. That check is not a sandbox for redirects, subresources, WebSockets,
private-address access or DNS. No browser security feature is disabled to connect.

## MCP session lifecycle

The server exposes two tools:

- `kelpie_worker_session` with a strict `request`: `create` with
  `options:{isolation:"isolated"|"shared",ttlMs?}`, `list`, `describe` or `close`
  with the returned `sessionId`.
- `kelpie_browser_control` with `{sessionId,request}`, using the canonical version
  1 browser request. Call `capabilities` for that backend's exact inventory.

For example:

```json
{"request":{"action":"create","options":{"isolation":"isolated","ttlMs":60000}}}
```

Then call the browser tool with the returned session id:

```json
{"sessionId":"returned-id","request":{"version":1,"method":"tabs.list","params":{}}}
```

Use an owned `tabId` from that result for page operations. Descriptors contain an
opaque session id, backend, isolation mode, owned tab ids and expiry, without human
identity attributes. The standalone stdio process uses an ephemeral local transport
principal. An integration with existing UOA authorization can retain its stable
subject reference; this feature creates no identity/profile database.

Sessions last 1 second to 1 hour, default 5 minutes, subject to the configured
maximum. When an operator sets a maximum below 5 minutes, callers must explicitly
request a duration within that bound. Session and tab limits each range from 1 to
16, default 4. Expiration rejects further operations and closes owned resources.

Isolated mode creates a fresh browser context with service workers blocked and
downloads disabled. Playwright shared mode uses a fresh automation context created by this
worker process; its sessions share that explicit context's cookies/storage.
Existing CDP/default/human contexts and pages are never enumerated or imported.
Each session owns only its newly created tabs, and popups are not promoted into
agent-owned handles. Unsupported real isolation is refused rather than simulated.

Closing a session leaves the borrowed browser process and shared context alive.
Worker shutdown closes its sessions and its own shared context, then disconnects
the external CDP connection. The pinned Playwright implementation's CDP
`browserProcess.close` closes its transport rather than sending `Browser.close`;
the real interface acceptance must additionally confirm unrelated contexts remain.
See [Playwright's pinned CDP implementation](https://github.com/microsoft/playwright/blob/26a9e470a7b3c7822084b09fb7f13902c5f37b51/packages/playwright-core/src/server/chromium/chromium.ts).

## Restricted Lightpanda profile

Set `backend:"lightpanda"` only for an operator-managed Lightpanda process.
`verifiedLightpandaMethods` is an explicit operator list of compatible methods from
the adapter's conservative candidate inventory. The default list is empty, so
only documentation/capabilities are available until verification admits methods.
A method is never enabled by editing a model request or public capability result.


For the tested 1.0.2 binary, diagnostics observed one context and one page at a
time. Use maxSessions: 1 and maxTabs: 1, and isolated sessions only. Shared sessions
return ISOLATION_UNAVAILABLE before creating or using any shared context, in
both the SDK and public worker factory. This refuses an unverified storage mode;
it never substitutes borrowed/default storage.

The minimal navigation inventory verified through the built production stdio CLI is tabs.list/tabs.close,
tab.goto/tab.url/tab.title/tab.back/tab.forward/tab.reload. tabs.new and the
snapshot/extract/status/ready reader family remain unadmitted publicly. Passing
a limited fixed-reader diagnostic does not establish the full reader contract.
The seven-case production stdio corpus passed for exact 1.0.2 with one isolated session/tab; no visual/input/WebMCP
support is inferred from these diagnostics.

No canonical screenshot, visual geometry, pointer motion, tap effect, GIF or video
capture is available from this backend. Its upstream text-layout images are not
real browser pixels. Do not import human cookies/profiles or attach a model-chosen
endpoint as a compatibility workaround. There is no automatic backend fallback.

The [Lightpanda analysis](../plans/browser-automation-capture/lightpanda-analysis.md)
records exact upstream revisions and the bounded real-binary diagnostics, including
failures, completed narrow production acceptance and pending reader expansion.
Passing protocol or mock tests alone does not establish compatibility.

## Experimental WebMCP controller

The portable `createWebMcpController` API operates fixed
`document.modelContext.getTools/executeTool` browser calls when actually available.
It requires a trusted binding to select the audited input encoding (json-string for Chromium151, object for the current specification) and supply an existing authenticated session, exact
origin, document generation and explicit per-operation authorization. The model's
requested origin never creates a grant.

Tool metadata and results are bounded untrusted data. Discovery is explicit; no
tool is automatically invoked. Every invocation is treated as a mutation
regardless of `readOnlyHint`. Ref changes, toolchange/navigation, revoked grants,
timeouts and unknown completion retain their own refusal/uncertainty behavior.

Canonical/native exposure requires its separately integrated schema, an actual API
probe and a trusted operator grant. A fixed reader alone does not authorize or
enable native support. The operator launch-only native origin setting is default
empty; no HTTP/model self-grant setter is introduced. This portable controller
does not claim that WebKit, Android WebView, CEF or Lightpanda implements the API.

## Verification

The durable real interfaces are:

- `node tests/native/managed-worker-acceptance.mjs`: disposable Chromium ownership,
  isolation, shared-tab privacy and expiry; an optional operator-owned loopback
  Lightpanda endpoint exercises only its explicitly tested candidates.
- `node tests/native/webmcp-acceptance.mjs`: actual API shape, explicit feature flags,
  discovery/invocation, permission refusal, ref invalidation and bounded uncertain
  results. An absent API is recorded as unavailable, never replaced by a polyfill.

Safe reports go under `KELPIE_TEST_ARTIFACT_DIR`; set
`KELPIE_TEST_REVISION` to the tested commit. Actual runtime results are tracked in
[the desktop/backend ledger](../plans/browser-automation-capture/desktop-backend.md).

## Explicit managed WebMCP grant

WebMCP is disabled by default. To enable it for a tested browser API, the operator
adds both fields to startup configuration:

```json
{
  "webMcpOrigins": ["https://example.com"],
  "webMcpInputEncoding": "json-string"
}
```

This gate is implemented for verified Playwright-backed Chromium only; the restricted Lightpanda profile refuses site tool configuration until separately verified.

The origin list must be an exact subset of allowedOrigins. The input encoding is
an audited browser-runtime choice: Chromium151 uses json-string, while the current
specification uses object. Unsupported encodings are refused before invocation.
These settings cannot be changed by lifecycle or browser tool arguments.

Navigate an owned tab to a granted origin, then call capabilities. Canonical
tab.webmcp.discover/call appear only after an actual private-world API probe
succeeds on an owned eligible page. For page-driven navigation, request capabilities
with that tabId to refresh availability. A missing API or private world does not
become a polyfill fallback.

Discovery params are {origin,maxTools?,maxChars?}. Invocation params are
{origin,ref,input?,timeoutMs?}, using the opaque ref returned by that document's
latest discovery. No endpoint, owner, encoding or origin grant is accepted in the
request. Every call is structurally mutating even when publisher hints say read
only. Native app exposure remains separately gated and is not implied by a worker
capability.

Managed probes and calls use a private main-frame CDP world without universal
access, reached only through the already owned Page. Page-authored modelContext
shadows cannot turn a page shim into browser API support. Current authenticated
session, exact browser origin and actual execution-context identity are checked
around dispatch; no cross-frame tool delegation is introduced.

A deadline may request AbortSignal cancellation. An abort rejection is not proof
that a page executor stopped: completion stays BUSY until an actual late reply
retires it or the trusted host confirms exact page/context teardown. A URL, hash
or history change does not clear that fence. Closing the owned tab/session remains
the supported recovery path; an uncertain mutation is never replayed.

Failed allocation cleanup remains owned, counts against resource limits and
retries with bounded backoff while the host is alive. CLEANUP_PENDING is not a
successful release. This applies to pages created before admission, initial
session failures and registry allocations whose later admission fails.

The production bundle corpus is
node tests/native/worker-stdio-acceptance.mjs. It uses the actual
packages/cli/bin/kelpie.js worker entrypoint, two shared sibling sessions and their
popups, isolated storage, public observations, explicit WebMCP grants/refusals,
borrowed-endpoint survival and stdout JSON protocol integrity. The Maxis corpus passed on sandbox-enabled headless Chromium151.0.7922.34; see the exact candidate, versions, hashes and limits in the desktop/backend ledger.
