# Managed worker and WebMCP source review

Reviewed checkpoint: 28a9f3c71c81f3df6e87ac77b69d49363391cb2d.
Review mode: read-only source plus owner-reported evidence. Acceptance started no
browser, worker, native process or Computer Use session.

## Findings

| ID | Invariant and exact source | Required result |
|---|---|---|
| BACK-01 | webmcp.ts admit checks disposed before awaiting identity/authorize, but run checks only pending. dispose can finish while admission is suspended, then the admitted operation starts | Recheck disposal immediately before dispatch. Suspend authorization, dispose, resume, and assert evaluate is never invoked |
| BACK-02 | managed-session.ts newTab tracks a page only after its second admit. If admission and page.close both fail, the page is absent from pages. Initial allocation and automation-sessions.ts create also swallow close failures before rejecting, losing the session handle | Record ownership before the next await. Retain failed cleanup ownership after failed allocation/registry admission and retry automatically without restoring access |
| BACK-03 | webmcp-json.ts Reflect.ownKeys materializes all keys before the property budget; JSON.stringify(key) runs before an explicit key-length check. webmcp-reader.ts encodes the entire result string before checking its byte cap | Bound copied key/string work before serialization; use bounded enumeration where possible and document unavoidable browser API materialization |
| BACK-04 | managed-worker-acceptance.mjs tests one managed session in a shared context beside a human page | Add two managed siblings with each opener's popup. Closing/expiry of one must preserve the other session and human page |
| BACK-05 | WebMCP actual-API timeout corpus observes BUSY immediately after timeout, then waits beyond completion. It does not prove the fence persists if browser abort rejects before the underlying site task stops | Observe a second attempt during the remaining task interval. If completion is unknowable after API rejection, preserve an uncertainty fence or require renderer/session retirement |

The owner accepted BACK-01 through BACK-04 and is preparing fixes and regressions.
BACK-05 is an evidence question sent to the owner, not a reproduced actual-browser
failure. None is closed by this checkpoint.

## Ownership and shutdown assessment

allocateManagedBrowserSession imports no existing page handles. Isolated sessions
own a fresh context; explicit shared sessions own only fresh pages. Popup
listeners attach to each owned page, not to the whole context. This avoids the
specific design hazard where each session's context-wide listener closes a
sibling session's new page. Popups are refused and closed rather than silently
admitted. Failed popup closure remains in a retained set for later cleanup.

Admission is repeated around asynchronous authorization, navigation and command
completion. Mutation results that lose access after dispatch become uncertain.
The timer retires access on TTL expiry. Normal failed session close retains its
page map for a later explicit retry; BACK-02 concerns the earlier allocation
failure paths where that owner is never returned.

The operator config chooses the CDP endpoint, backend, origins and maximum
sessions. Tool arguments cannot attach to arbitrary endpoints. The stdio worker
creates its own shared context and binds one opaque owner to that transport.
The network callback limits requested top-level navigation only. Subresource
egress and DNS enforcement remain an explicit operator responsibility.

The source calls browser.close during worker shutdown. The owner documents that
the pinned Playwright connectOverCDP connection disconnects its borrowed browser
rather than terminating the external browser. Verify this through the public
stdio flow against the actual pinned version; session unit tests alone do not
prove external browser survival.

## Capability and trust assessment

The restricted Lightpanda adapter admits only its private verified method set.
It does not advertise screenshots, geometry, pointer input or canonical DOM
observations without backend evidence. Mutating the public capability object
does not enlarge the private admission set. Actual Lightpanda execution remains
pending; Chromium is not a substitute for that result.

WebMCP uses fixed reader/action source and a host-selected input encoding.
Discovery and invocation require host grants for the current session, exact
origin and document generation. Page hints never grant authority. Tool metadata
and results are labelled untrusted; accessors, unsupported values and excessive
structures are refused. Error text is fixed rather than copied from page
exceptions. Tool references belong to an observed document catalogue and are
consumed on invocation. Navigation/tool changes invalidate the registry.

The controller and page helpers are exported implementation pieces. Canonical
worker/native browser-control exposure is not wired at this checkpoint. A helper
corpus pass must not be described as shipped native WebMCP support.

## Evidence and remaining gates

The owner reports shared 120 tests and CLI 632 tests passing with 64 existing
skips, plus actual headless Chromium 151 ownership and WebMCP corpora. The inspected
WebMCP evidence file is
D:/BuildArtifacts/kelpie/capture-desktop-20261104/acceptance/webmcp-actual-api.json:
it records Chromium 151.0.7922.34 with WebMCP/WebMCPTesting flags, actual
document.modelContext, json-string input, and revision label
5db4e2d6+audited-json-string. That label is not an immutable final source SHA;
rerun and record the final integrated revision for acceptance.

Durable tests are packages/shared/tests/managed-session.test.ts,
packages/shared/tests/webmcp.test.ts,
packages/cli/tests/browser/automation-sessions.test.ts,
tests/native/managed-worker-acceptance.mjs and
tests/native/webmcp-acceptance.mjs. The public stdio entry point, actual LP
endpoint, compiled Windows app, native MCP/CLI and installed release remain
pending. Canonical OWN-01/02, LP-01/02 and WEB-01/02 are not closed.
