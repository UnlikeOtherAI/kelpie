# Lightpanda: applicability and restricted integration analysis

Research date: 2026-11-04. Kelpie integration base inspected:
`c01b2038bdb663cb9d5c7add134d587635da17ca`.
No upstream implementation source is copied into Kelpie.

## Decision

Use Lightpanda as an optional, separately operated worker for a proven subset of
navigation and public DOM/text tasks. Keep native Kelpie and Chromium for real
rendering, semantic button-center geometry, pointer/tap presentation, screenshots,
walkthrough GIF/video and native platform acceptance. These are different
capabilities, not interchangeable evidence.

Admit a worker method only after the exact installed binary passes its
deterministic corpus. A CDP handshake proves transport connectivity, not page
correctness, secrecy, storage isolation or complete Playwright compatibility.

## Upstream revisions and provenance

| Item | Verified reference | Meaning |
| --- | --- | --- |
| Repository | [lightpanda-io/browser](https://github.com/lightpanda-io/browser) | Upstream project; not a Chromium/WebKit fork |
| Latest stable release returned by GitHub | [1.0.2](https://github.com/lightpanda-io/browser/releases/tag/1.0.2), published 2026-10-23 | The release API returned this tag during research |
| Stable source commit | [c5f7bb29b127040c899d4e181b5709f76fc71a6f](https://github.com/lightpanda-io/browser/commit/c5f7bb29b127040c899d4e181b5709f76fc71a6f) | Commit directly referenced by tag 1.0.2 |
| Main inspected | [576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db](https://github.com/lightpanda-io/browser/commit/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db), 2026-11-04 | Development source, not a claim about the stable binary |
| Development manifest | [build.zig.zon at inspected main](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/build.zig.zon) | Declares 1.1.0-dev and pinned dependencies |
| Linux x86_64 release asset | 76,408,136 bytes; GitHub digest `sha256:ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e` | Expected release metadata only; no downloaded binary was verified in this research step |

The last row comes from the [GitHub release API](https://api.github.com/repos/lightpanda-io/browser/releases/tags/1.0.2).
Acceptance must additionally hash the bytes actually run and record executable
version, architecture, launch flags, operating system and test revision. A moving
nightly download must never be silently called the inspected stable release.

## Architecture and expected tradeoffs

The project implements a headless browser in Zig around HTML/DOM, V8 JavaScript
execution, networking and browser APIs. Its dependency manifest includes its V8
fork, curl, BoringSSL and other pinned components. Removing a full graphical
rendering pipeline can reduce work for DOM-oriented tasks; it also changes which
browser facts exist. This is architectural reasoning, not a measured Kelpie speed
or memory result.
See [the inspected manifest](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/build.zig.zon).

The [CDP implementation](https://github.com/lightpanda-io/browser/tree/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/server/cdp/domains)
implements protocol domains individually. Kelpie must test the methods it uses,
their asynchronous lifecycle and result semantics. A Playwright adapter starting
with the entire Chromium method catalogue would overstate this partial backend.

The [ToolSession implementation](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/ToolSession.zig)
owns a separate browser/V8 environment, session, notification state and node
registry; restart replaces page/storage/history state. This supports investigating
explicit worker lifetimes, but does not independently prove that a particular
CDP BrowserContext API isolates cookies/storage correctly. Our actual supported
interface must establish that separately.

The [Element implementation](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/browser/webapi/Element.zig)
derives document position from DOM structure rather than a full visual layout.
Successful getBoundingClientRect/getClientRects calls therefore cannot establish
pixel-accurate centers, occlusion, clipping, responsive placement or native input
parity. Never feed these coordinates into a native screenshot walkthrough.

The [page CDP domain](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/server/cdp/domains/page.zig)
exposes screenshot/PDF protocol entry points. Upstream's
[README at this revision](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/README.md)
describes text-only PNG/PDF output. Protocol naming is not a real rendered-pixel
guarantee. Kelpie must refuse canonical tab.screenshot and capture artifacts for
this backend even when the upstream protocol can return image bytes.

The [structured-data collector](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/browser/structured_data.zig)
demonstrates deterministic publisher metadata extraction and explicit expansion
limits for recursive microdata. The transferable idea is bounded structured
evidence with provenance; Kelpie implements its own policy-aware collector.
Raw JSON-LD, OpenGraph or semantic-tree content remains publisher-controlled.
Its presence does not establish truth, authority or safe values.

The [SemanticTree implementation](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/SemanticTree.zig)
is relevant to compact task context. Kelpie must preserve its own value-free
contract rather than import a richer upstream dump that might contain form
values, editor content or page-supplied instructions.

## Applicable Kelpie flavors

| Kelpie flavor | Useful application | Limits and acceptance target |
| --- | --- | --- |
| CLI / SDK / MCP host | Operator allocates a short-lived external worker and exposes an exact method profile to a caller | No model endpoint attach; no implicit fallback; real navigation/text/extraction corpus first |
| macOS WKWebView | Can request a separate external worker for an independent DOM task | Does not replace WebKit cookies, visible UI, capture or private-world native checks |
| macOS CEF | Compare identical DOM tasks with the external worker | CEF remains the rendering and native interaction baseline; worker results cannot prove CEF correctness |
| Windows CEF | Windows client may use a separately operated worker | Upstream has no native Windows binary; Maxis currently has no WSL. Do not install WSL or port an engine implicitly |
| Linux CEF | Optional external Linux worker for compatible DOM tasks | Keep CEF for pixels/UI/input; process/network boundaries remain operator obligations |
| Linux no-CEF | May serve control metadata and reach a separately allocated worker through an explicit backend | No-CEF does not acquire a native DOM/rendering capability because a remote worker exists |
| iOS / iPadOS | Foreground native app may explicitly delegate a separate task through an authorized service | No native Lightpanda engine, session-cookie transfer, Apple engine approval or mobile background execution is implied |
| Android | Same explicit remote-worker distinction | Upstream Linux aarch64 is not an Android binary; Android Bionic is not the Linux glibc ABI |
| Native local / remote inference | Consume bounded authorized results through existing policy | Worker content is untrusted evidence, never a second identity authority or tool-permission grant |

The platform binary statements come from
[the pinned README](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/README.md).
The existing Kelpie renderer matrix and source paths are in
[browser-engines.md](../../browser-engines.md). Availability upstream is distinct
from our installed, tested or released support.

## Security, resources and identity

An external process is a boundary to operate and verify; it is not evidence of
equivalence to Chromium's sandbox. This research did not perform a complete
security audit. The [upstream security policy](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/SECURITY.md)
states that security fixes land on latest main. Pinning a stable binary therefore
also requires checking applicable upstream fixes before operational use.

Keep the worker on an explicitly managed endpoint with enforced process CPU/RAM,
lifetime, network egress and download limits. A top-level URL allowlist does not
constrain redirects, subresources, WebSockets, private addresses or DNS rebinding.
Do not disable CORS, TLS validation or a native sandbox to make the corpus pass.

Kelpie's proposed managed allocator creates a fresh isolated context, or fresh
owned tabs in an explicitly selected shared automation context. It never
enumerates/imports human tabs, copies cookies from human sessions or closes the
borrowed browser process. TTL, max-tabs and per-call authorization are separate
from external process resource enforcement.

UOA remains the sole identity authority. Store no duplicated human profile,
password or membership records. The internal owner reference is an existing
stable subject; model-facing session descriptors contain opaque session/tab
identifiers, backend, isolation and expiry rather than identity attributes.

## Licensing facts and integration boundary

The inspected [LICENSING.md](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/LICENSING.md)
identifies AGPL-3.0-only as the default project license and points to
[LICENSE](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/LICENSE).
Some individual source headers have their own wording; do not replace the
repository's license statement with an assumption based on one header.

Our implementation is independently authored protocol/client code. It does not
copy, statically link, bundle or port upstream source/binaries. The operator
installs the external worker. This describes the proposed technical boundary;
it is not a legal conclusion that any use, distribution or modification is
exempt from license obligations. A future bundling/distribution decision requires
a separate review of the exact artifacts and their licenses.

## Independently adopted ideas

- Compact task-directed observation instead of dumping entire pages.
- Deterministic extraction and publisher metadata with source/document provenance.
- Explicit isolated sessions, owned references and bounded lifetimes.
- Exact capability inventories instead of assuming protocol-level parity.
- Reusable scripts whose replay does not require a language model for every step.
- Differential task correctness and cost measurements with reproducible failures.

Kelpie's shared collectors, script schemas and ownership policy are the source of
truth for these features. The adoption is architectural, not source translation.
Existing form/editor omission, native input semantics and uncertain-completion
rules remain required.

## WebMCP relationship

Upstream main includes an explicit
[WebMCP CDP domain](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/server/cdp/domains/webmcp.zig)
and a [ModelContext implementation](https://github.com/lightpanda-io/browser/blob/576b6c512a5b768d4e3bdc3db18ac21c1d1ea3db/src/browser/webapi/ModelContext.zig).
They expose registration/discovery/invocation and cancellation behavior. Their
presence on development main is not proof of the 1.0.2 release API or Kelpie
conformance. The real binary corpus must establish availability and behavior.

The inspected [WebMCP specification](https://github.com/webmachinelearning/webmcp/blob/6cd745ac8a186122bd3f4aeaeb1d6cfa820251d2/index.bs)
uses document.modelContext.getTools and executeTool with RegisteredTool objects.
Kelpie's pinned [Playwright 1.62.1](https://github.com/microsoft/playwright/tree/26a9e470a7b3c7822084b09fb7f13902c5f37b51)
predates the convenience API documented as added in
[Playwright 1.64](https://playwright.dev/docs/api/class-webmcp).
Use fixed functions against the actual enabled browser API rather than inventing
support or silently polyfilling it.

WebMCP tool names, descriptions, schemas, annotations and results are untrusted.
Discovery and invocation require an explicit existing session/origin/document
grant. Invocation is structurally mutating regardless of readOnlyHint. No page
declaration can authorize endpoints, evaluation, identity changes or tool calls.

## Measurable compatibility and cost plan

Use the same frozen fixture/corpus revision for Chromium and Lightpanda, with no
live public-site timing claims. Keep runtime versions, architecture, worker flags,
egress policy and binary hashes alongside results.

| Corpus area | Required result | Failure to preserve |
| --- | --- | --- |
| Navigation and metadata | Exact URL/title after initial load, redirect, reload and back/forward where admitted | Timeouts, unsupported methods, wrong document/title |
| Public extraction | Expected public text/links/publisher metadata, deterministic bounds/provenance | Missing facts, wrong truncation, hidden-content exposure |
| Value omission | No input, textarea, editable or referenced editable secrets | Any leaked fixture secret, even when task otherwise succeeds |
| Ownership | Foreign/closed/expired tab refusal; isolated storage; shared explicit cookies only | Cross-session access or hidden browser.close ownership |
| Readiness | Actual supported evidence; unavailable network/error data remains unavailable | False-ready or invented zero-error/network counts |
| WebMCP | Actual API-enabled discover/call; grant/ref invalidation; bounded result; uncertain timeout | Polyfill-only pass, hint-based permission, replay or unbounded metadata |
| Visual boundary | Canonical screenshot/geometry/pointer/capture refused for LP | Any text-layout image represented as real pixels |

Record task success against independent fixture expectations before cost.
Measure cold startup separately from warm tasks, wall time distribution
(median/p95), process-tree peak RSS, CPU time, request/tool counts, response bytes
and any model token/cost figures actually observed. Use repeated bounded runs,
fixed concurrency and a documented timeout. Keep incompatibilities in the
denominator; do not compare only successful or favorable tasks.

A DOM task passing on LP does not establish responsive layout, trusted native
activation, accessibility platform behavior, browser screenshots, video frame
timing or OS/browser integration. Those require the real native/Chromium flow.

## Evidence status

| Evidence | Completed | Pending |
| --- | --- | --- |
| Source/release/API research | Commit-pinned sources; exact 1.0.2 executable size/hash/version verified | Future release compatibility |
| Independent session/backend source | eee84a26 plus checked 9a301405; shared/CLI full checks passed | Installed published package gate |
| Real Chromium session corpus | Actual production stdio/private-world WebMCP corpus; see desktop-backend.md | Native platform flows are separate |
| Real LP CDP navigation/text/extraction | Narrow production navigation profile and limited diagnostic facts below | Full reader/privacy/visibility corpus expansion |
| Compatibility/performance comparison | Five bounded attempts with absolute correctness/cost evidence | Comparable same-host Chromium runs; no ratio claimed |
| Native Windows/Linux capture | Not evidence for LP | Separate native owner/rollout gate |

Never convert a pending row into completed support because a unit mock or a
protocol handshake passed.

## Measured stable-binary compatibility, 5 November2026

Four disposable Fedora44 runs used the exact official1.0.2 binary (SHA-256
ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e),
Playwright1.62.1 and the permanent frozen capture fixture. Every run was under
the independently verified loopback-only packet-egress/cgroup boundary:
oneCPU, CPUWeight1,2GiB,64 tasks and120s maximum. No codec/native app build,
human profile or background service was involved. All LP processes exited and
all collected units ended inactive/not-found with MainPID0.

| Source | Named checks | Result and retained limitation | Whole-service cost |
| --- | --- | --- | --- |
| 1a182318 | 0 | Setup failed at second context; no task success inferred |1.477s wall/1.402s CPU/187MiB peak |
| 754503ba |2 | Extra page refused; URL test expected a noncanonical missing slash |1.544s/1.468s/183.4MiB |
| 8cfe75c5 |16 |11 passed,5 failed; includes upstream limits and two invalid fixture expectations |1.752s/1.700s/191.4MiB |
| c774ac3a |19 |15 passed,4 failed; controls/heading bound still needed correction |2.219s/2.167s/189.8MiB |

Counts are per evolving diagnostic revision, not a blended compatibility score.
All setup, test and refusal results remain in the evidence. These whole-service
costs include Node/client/fixture setup and run under host contention; they are
neither LP-only consumption nor an unloaded speed comparison. The last kernel
cgroup peak was199065600 bytes with2.106386 CPU seconds before final report/exit;
quota throttling was observed. Individual cold/warm task samples remain in JSON.

Observed support within this fixture:
- Navigation, title/URL, history back/forward and reload completed correctly.
- Deterministic product extraction returned exactly Green tea/Black tea despite
  hidden, inherited-hidden and editable/value canaries; none appeared in the
  tested result. Document/viewport status and visible/hidden readiness checks
  passed. Missing/ambiguous/nested extraction and opacity/collapse cases remain
  outside this diagnostic proof.
- Closing a context then creating another omitted prior synthetic cookies and
  local storage. One managed isolated session with maxTabs1 passed owned-tab,
  foreign-tab, unsupported-method and close/fresh-context checks.
- A second concurrent context refused, as did a second page. Explicit shared
  multiple-tab ownership could not operate. This requires conservative host
  admission; it does not justify silently sharing a context or importing a page.
- Actual document.modelContext was undefined. No site tool, canonical screenshot,
  geometry/pointer or pixel/native-flow capability was admitted.

The snapshot failure is inconclusive as backend evidence: the harness requested
prioritized maxElements20 but required a heading after24 visible priority0
controls. It also omitted the internal host prefix. The actual20-control result
had no private canary. Independent common-owner source review confirmed that
expectation was invalid. Corrected bounded/scoped snapshots must be exercised;
we do not claim either parity or incompatibility from this failed assertion.

No production worker stdio session was attempted in those first four diagnostics.
The later seven-case production checkpoint below proves only its explicit
navigation inventory. No public reader profile has been enabled; proposed reader
expansion remains a separate full-contract gate.

Reports and service/teardown logs:
D:/BuildArtifacts/kelpie/capture-desktop-20261104/lightpanda-actual.
The final c774ac3a-report.json SHA-256 is
34e0239a682ded2224efde52b6721264968a513a46eeaa3235d212ce38d052a0.
These are generated evidence artifacts; only the hand-authored corpus and
conclusions are committed.

## Verified production stdio navigation profile, 5 November 2026

The built production CLI/SDK at 9a30140514720ad34fe71e1a065b8de0209b5f00
passed all seven public stdio cases from fixture revision
0a6913f700f16080b47244f322a23ced23cebe65 on the exact 1.0.2 Linux asset above.
CLI/package/MCP initialize all reported 0.1.22. The archive SHA-256 was
2fa04e2e4cec3ae06c33047fc8c4bd84a0283135aaaa6a5389139cab7556a989.

The operator configured one isolated session and one tab. Verified methods were
tabs.list, tabs.close, tab.goto, tab.url, tab.title, tab.back, tab.forward and
tab.reload, alongside documentation/capabilities. Shared isolation refused before
allocation; a second session refused RESOURCE_LIMIT. Actual history/reload,
foreign-tab and origin refusal, closed/stale handles, fresh cookie/localStorage
isolation, TTL retirement and clean stdio shutdown all passed. A fresh context
on the borrowed LP endpoint still worked after worker shutdown. No human storage
or pages were imported. Unsupported readers/input/pixels/WebMCP stayed refused;
the corrected diagnostic snapshot assertions remain separately unexecuted.

The enforced unit retained one CPU/CPUWeight 1, 2 GiB, 64 tasks, 120 seconds,
NoNewPrivileges and loopback-only egress. There were 41 tool calls and 3,999
response bytes. Whole-service cost was 7.464 seconds wall, 4.280 seconds CPU,
301.1 MiB peak; the report measured 6.462 seconds including teardown and a
315,830,272-byte cgroup peak before exit. Quota throttling and host contention
were present. These are one absolute sample, not a same-host engine comparison.
Earlier four diagnostic attempts/failures remain in the denominator and table.

Unit kelpie-lightpanda-public-1793850018 exited successfully, then was collected:
not-found/inactive, MainPID 0, cgroup absent, no LP process. Worker stderr was
empty and stdout remained valid MCP. Evidence on Maxis:
D:/BuildArtifacts/kelpie/capture-desktop-20261104/lightpanda-actual/public-9a301405,
including report.json, journal.txt, unit-begin.txt and teardown.txt.
Report SHA-256:
d7ca0d84efe7f232bb508443af655790cd0d6447b56a275e47f85261c7f63267.
An initial artifact-copy wildcard encountered the synthetic empty-home directory;
explicit report-file transfer then succeeded with the same verified report hash.
No corpus result was changed. No ongoing worker service remains.
