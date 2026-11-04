# Landed implementation and evidence map

This map links canonical requirements to reviewed source checkpoints. A source
checkpoint or portable test does not close native acceptance. The authoritative
requirements remain in [acceptance.md](acceptance.md). All native app, displayed
overlay, direct MCP/CLI, remote artifact and installed-release evidence is
**pending** unless a later exact-revision record explicitly says otherwise.

## Checkpoint keys

| Key | Exact source checkpoint | What was reviewed |
|---|---|---|
| OBS | e52240e7fe127b4b43aac51fd4eb2db4e64dd574 | Canonical observations and generated native ABI |
| WFL | d6d7a36666e11db45e7e42cfe09a62d1f2a2fcd8 | Strict workflows, bindings, target safety and presentation |
| CODEC | 8369571f6b821cc4bcfc853de2a78f5fc25e142d | Windows codecs, exclusive output opens, failure cleanup and decoded color checks |
| BACKEND | 28a9f3c71c81f3df6e87ac77b69d49363391cb2d | Managed sessions, restricted LP and WebMCP helpers |
| QA | d81d6283df63e2c26c1aebbca8afd8a09facc8ec | Independent target regressions and observation review |
| FIXTURE | 4fbd5e4ed4d0c2873eb632c4d12f96c91267c03a | Real DOM race triggers for future native runs |

Integration may cherry-pick these commits under different hashes. Record the
actual integrated source and binary hashes when running native acceptance.
Uncommitted observation/runtime follow-ups are not mapped as landed. The Windows
runtime draft tree is reviewed separately in windows-runtime-review.md.

## Durable eval keys

Paths below are repository-relative. Each key names permanent tests, not a claim
that every platform ran them.

- **OBS-SCHEMA**: packages/shared/tests/browser-observations.test.ts:
  "bounds nested extraction and rejects arbitrary value/attribute/code sources";
  "makes readiness immediate and all observations read-only";
  "authorizes every observation before resolving an owned page and scrubs results".
- **OBS-BROWSER**: packages/shared/tests/browser-control.browser.test.ts, both
  playwright and native-transport fixtures: "prioritizes scoped action evidence
  without values"; "extracts nested records with explicit ambiguity and publisher
  provenance"; "reports explicit readiness and unavailable diagnostics".
- **ABI**: native/core-mcp/tests/test_browser_gateway.cpp, generated request/
  extension/script/target normalization and fixed-reader dispatch checks.
- **WORKFLOW**: packages/shared/tests/script-workflow.test.ts: strict actions and
  capture, typed input binding, secret reference/capture rejection, artifact read
  bounds, C/S endpoints/easing and wobble/fade timeline.
- **TARGET**: packages/shared/tests/script-target.test.ts: visible clipped center,
  moved/obscured/detached target refusal, exact descendant replacement,
  document-token namespace, traversal bound, and parameterized focus mutations.
- **TARGET-INDEPENDENT**: tests/capture/target-regressions.test.mjs: seven tests
  for visible center, detached descendant, focus URL/readonly/type/viewport,
  and old-document token rejection. All seven passed against WFL in 96 ms on
  Maxis Node 24.19; these are source-level stubs.
- **CODEC-DECODE**: apps/windows/tests/script_media_encoder_test.cpp:
  Timing, AbortAndValidation, Budget(gif/mp4), StepBudget, GifRounding,
  SmallBudgets, ExclusiveOwnership, PngFailureCleanup and GifPaletteChanges.
  WIC decodes images and Media Foundation decodes MP4 samples.
- **MANAGED**: packages/shared/tests/managed-session.test.ts;
  packages/cli/tests/browser/automation-sessions.test.ts;
  tests/native/managed-worker-acceptance.mjs (actual Chromium, LP still pending).
- **WEBMCP**: packages/shared/tests/webmcp.test.ts and
  tests/native/webmcp-acceptance.mjs (actual flagged Chromium API).
- **FIXTURE-EVIDENCE**: tests/capture/fixture.html, fixture.js, assertions.mjs,
  evidence.mjs and harness.test.mjs. Synthetic page, event oracle, evidence
  validation; six harness checks passed. Native use remains pending.

## Requirement-to-source map

| Canonical IDs | Source symbols/files | Durable evals | Checkpoint and remaining work |
|---|---|---|---|
| OBS-01 | collectBrowserSnapshot in browser-control/snapshot.ts; collectBrowserExtraction in observations.ts | OBS-BROWSER private canaries; FIXTURE-EVIDENCE assertValueFree | OBS; native pending, bounded-reader follow-up open |
| OBS-02 | BrowserSnapshotOptionsSchema; collectBrowserSnapshot scope/priority | OBS-SCHEMA, OBS-BROWSER scoped actions | OBS; native pending |
| OBS-03 | snapshot clean/content/visit; extraction bounded/publicText | OBS-BROWSER output limits | OBS; work-before-budget defect open |
| EXT-01 | BrowserExtractionOptionsSchema; collectBrowserExtraction extract | OBS-SCHEMA, OBS-BROWSER missing/ambiguous/source cases | OBS; native pending |
| EXT-02 | extractionField(depth); extract nested records with recordsRemaining/fieldsRemaining | OBS-BROWSER nested catalogue/list records | OBS; bounded traversal follow-up open |
| EXT-03 | collectBrowserExtraction metadata/JSON-LD allowlists | OBS-BROWSER publisher/@graph/private canary cases | OBS; metadata-copy bounds follow-up open |
| EXT-04 | BrowserExtractedField.provenance; metadata selector/attribute; documentRevision availability | OBS-BROWSER provenance assertions | OBS; incomplete provenance follow-up open |
| RDY-01 | collectBrowserPageStatus; BrowserPageStatus | OBS-BROWSER unavailable network/errors and counts | OBS; visibility/bounded count follow-up open |
| RDY-02 | BrowserReadinessOptionsSchema; collectBrowserReadiness | OBS-SCHEMA immediate defaults; OBS-BROWSER hidden/visible/ambiguous selector | OBS; actual native wait loop pending |
| OWN-01 | allocateManagedBrowserSession in browser-control/managed-session.ts; createManagedSessionRegistry in cli/browser/automation-sessions.ts | MANAGED isolation, foreign handles, expiry and cleanup | BACKEND; failed allocation cleanup ownership fix open; public stdio/native pending |
| OWN-02 | Existing browser-control/proxy.ts authorization; native/core-mcp/src/browser_gateway.cpp dispatch; resolveScriptTarget token fence | OBS-SCHEMA authorization; ABI; TARGET | OBS/WFL; late callback, exact socket and durable Nessie pin native regression pending |
| WFL-01 | scriptV1Schema/scriptActionSchema in script-workflow.ts; kelpie_browser_validate_script C ABI | WORKFLOW, ABI | WFL/OBS; native preflight/legacy routing pending |
| WFL-02 | bindScriptInputs in script-bindings.ts; workflowValueSchema; sensitive flag | WORKFLOW secret/provider-error/input tests | WFL; native redaction and secret-target policy pending |
| WFL-03 | wait-ready/assert/output action schemas only | WORKFLOW shape checks; OBS-BROWSER extraction/readiness | WFL partial: reusable structured extraction and actual runtime ordering pending |
| WFL-04 | Contract states opt-in version 1; existing unversioned handler remains outside this checkpoint | Public legacy/v1 routing eval pending | No completed runtime mapping yet |
| WFL-05 | resolveScriptTarget unchanged fence and INPUT_UNCERTAIN result | TARGET, TARGET-INDEPENDENT | WFL; runtime stop/no-replay/lease recovery pending |
| TGT-01 | scriptTargetSchema; resolveScriptTarget role/name/label/selector resolution | TARGET uniqueness/ambiguity | WFL; real DOM/native pending |
| TGT-02 | resolveScriptTarget visibleBox and elementFromPoint check | TARGET clipped/obscured; FIXTURE-EVIDENCE center oracle | WFL; native coordinate dispatch pending |
| TGT-03 | visibleBox clipped rectangle; unchangedGeometry | TARGET-INDEPENDENT visible center/viewport | WFL; DPR/zoom/scroll real fixture pending |
| TGT-04 | captured Entry, unchangedGeometry, unchanged and post-focus checks | TARGET, TARGET-INDEPENDENT; FIXTURE child/focus races | WFL; real renderer pending |
| TGT-05 | ScriptTargetResult.inputGuarantee=synthetic-coordinate | FIXTURE event.isTrusted oracle | WFL declaration; Windows CDP actual guarantee still to be verified |
| PTR-01 | scriptPointerPosition in script-presentation.ts | WORKFLOW endpoints/C/S/ease; assertions.mjs trajectory oracle | WFL; native display/decoded motion pending |
| PTR-02 | shared numeric scriptPointerPosition and scriptTapPresentation | WORKFLOW deterministic numeric checks | WFL; compositor/native correspondence pending |
| VIS-01 | tapIndicatorSchema; codec BGRA input and NV12 conversion | CODEC-DECODE Y/UV and palette colors; future actual overlay pixels | WFL/CODEC partial; actual marker evidence pending |
| VIS-02 | scriptTapPresentation scale/alpha timeline | WORKFLOW wobble/fade | WFL; decoded early/middle/late frames pending |
| CAP-01 | ScriptMediaEncoder; WicGif; MfVideo; WriteStepPNG | CODEC-DECODE | CODEC only; actual script export pipeline pending |
| CAP-02 | WicGif::Write/Finish; Parse; cumulative centisecond boundary | CODEC-DECODE Timing/GifRounding | CODEC; changing-palette decode reported; visual playback pending |
| CAP-03 | MfVideo::Write/Pump/Retain/Finish; InputSample | CODEC-DECODE MP4 timestamps/full decode | CODEC; decoded chroma/failure checks reported; actual capture pending |
| CAP-04 | WriteStepPNG provides PNG encoding, not step scheduling/overlay | CODEC-DECODE StepBudget; FIXTURE-EVIDENCE | CODEC partial; every-step overlay screenshot runtime pending |
| CAP-05 | ValidateFrame/ AddFrame refuse dimension changes; shared target viewport/document fence | CODEC-DECODE invalid dimensions; TARGET | CODEC/WFL partial; asynchronous frame/document coherence pending |
| CAP-06 | scriptCaptureSchema; media::Budget; ValidateFrame; WriteStepPNG | WORKFLOW limits; CODEC-DECODE Budget/StepBudget | WFL/CODEC; minimum cap aligned; runtime duration/FPS admission pending |
| CAP-07 | one pending raw frame; capped MfVideo timings queue; GIF cumulative timing | CODEC-DECODE budget/timing | CODEC partial; sampler backpressure/drop/time correspondence pending |
| CAP-08 | ScriptMediaEncoder::Finish and successful output retention | CODEC-DECODE AbortAndValidation/next capture | CODEC partial; sibling-format recovery reported; native cancellation pending |
| ART-01 | scriptArtifactRequestSchema defines opaque chunk request only | WORKFLOW length bounds | WFL shape only; authenticated remote bytes/CLI retrieval pending |
| ART-02 | No artifact-owner runtime reviewed in these checkpoints | Two-owner/revocation native eval pending | Pending |
| ART-03 | scriptArtifactRequestSchema; WriteStepPNG lexical directory guard | WORKFLOW chunk bounds; CODEC-DECODE invalid path | WFL/CODEC partial; exclusive open fixed; failure-cleanup ownership question and transport tests pending |
| ART-04 | scriptArtifactSchema; ScriptMediaOutput codec metadata | CODEC-DECODE manifest timing/counts | WFL/CODEC partial; SHA-256, document provenance and partial state service pending |
| SEC-01 | value-free observations; bindScriptInputs safe errors/sensitive/capture checks | OBS-BROWSER private canaries; WORKFLOW secrets | OBS/WFL; runtime logs/progress/output scrubbing pending |
| SEC-02 | Fixed observation source; typed workflow excludes evaluate | OBS-SCHEMA; WORKFLOW arbitrary-code rejection | OBS/WFL; hostile-page real flow and WebMCP authority pending |
| DIF-01 | same fixed readers through Playwright/serialized native fixtures; assertions.mjs differential oracle | OBS-BROWSER both adapter fixtures | OBS/QA; actual platform corpus pending |
| LP-01 | createLightpandaBrowserBackend in browser-control/lightpanda.ts; private admitted method set | MANAGED capability/refusal cases | BACKEND; actual LP endpoint comparison pending |
| LP-02 | allocateManagedBrowserSession; worker/config.ts and worker/runtime.ts operator-only endpoints/origins | MANAGED owner crossover and unsupported visual methods | BACKEND; actual LP/public stdio lifecycle pending |
| WEB-01 | createWebMcpController in webmcp.ts; runWebMcpPageOperation in webmcp-reader.ts | WEBMCP actual API present/absent/discovery/call | BACKEND helper only; canonical/native exposure and dispose race fix pending |
| WEB-02 | WebMcpBinding identity/authorize/inputEncoding; boundedWebMcpJson; consumed document registry | WEBMCP hostile metadata, stale refs, timeout/uncertainty | BACKEND; bounded enumeration and persistent timeout fence evidence open |
| DOC-01 | docs/api/browser-control.md; docs/functionality.md; strict contract.md; generated schema source | OBS-SCHEMA, ABI; public examples still pending | OBS/WFL partial |
| UI-01 | No rendered product UI in reviewed checkpoints; numeric overlays only | Changed-state inventory/base-final pairs pending | Pending candidate |
| REL-01 | Coordinator integration/PR/version workflow | Required CI and source audit pending | Pending |
| REL-02 | Coordinator/platform published artifact installation | Signature/download hash/installed flow pending | Pending |

## Open review ledgers

- [Workflow review](workflow-review.md): reproduced defects, fixing revision,
  independent results and remaining bounded-name/runtime gaps.
- [Observation review](observation-review.md): bounded work, visibility, metadata
  provenance and generated ABI follow-ups.
- [Backend review](backend-review.md): managed allocation cleanup, WebMCP disposal,
  bounded data and real-interface evidence gaps.
- [Windows runtime draft review](windows-runtime-review.md): admission, asynchronous
  overlay timing, sample cadence, document provenance and native gates.
- [Windows codec review](windows-codec-review.md): byte-limit parity, partial PNG
  cleanup, exclusive file ownership, color and finalization-failure evidence.
- [Resources](resources.md): current platform gate and access history. Computer Use
  is off after the user's cursor-release request; do not infer UI authorization
  from an earlier connected viewer.
