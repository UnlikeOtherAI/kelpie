# Landed implementation and evidence map

Current reviewed integration snapshot:6f10b31bb724db74042ae7a40841ce4762ffe089.
Later owner-reported outcomes are labelled and never overwrite historical failures.
This maps all48 canonical IDs to landed source and durable checks. A source,
codec or compiled app is not a native semantic/UI pass. Actual reports remain
runtime-specific; all432 native cells require review. See acceptance.md,
evidence-intake.md and outstanding-gates.md.

## Current evidence supplement

The rows below retain original checkpoints. They are not the latest binary for
every runtime. Current stage outcomes at root6f10 and later owner reports:

- Portable shared/CLI allocation guards passed full required checks: shared140,
  CLI697 passed with one existing skip. Exact noCEF registry/profile/gateway/
  extension/desktop MCP checks passed4/4 on the authorized Minis test mirror.
- Android shipping JNI x86_64 link115/115,APK/test APK assembly and instrumentation
  compilation passed. Actual phone6/11 and replay10/12 failures remain historical;
  corrected hosted phone/tablet corpus and privacy fix runtime remain pending.
- iOS hosted41957712925 built app/tests/CLI at2e08956f,selected iPhone17/iPadAir,
  but iPhone container/scheduling cleanup failed and iPad was withheld. Authorized
  hosted rendezvous correction supersedes the old local-handoff blocker.
- Mac hosted41950256231 build succeeded; WK/CEF profile relink and3 native core
  checks passed. New hosted runtime corpusb027/91ff has not supplied accepted
  renderer runtime results here.
- Lightpanda actual diagnostic reports and operator boundary are audited in
  lightpanda-independent-review.md. Later owner-reported public stdio9a301405
  passed7/7 with41 calls; exact report intake remains a separately tracked step.
- Current privacy/source and actual protocol call gaps are finite in
  privacy-protocol-readiness.md. Source registration/discard fixes are not
  blanket native privacy acceptance.

## Historical checkpoints and still-current source anchors

| Key | Exact source | Scope / limits |
|---|---|---|
| OBS-FIX | 58e073c199c0c94e4f5e18d15b769f9eba1d403a | Raw metadata index and explicit scoped-root fixes; shared/real Chromium/core checks passed. |
| LABEL | 2a39d42c75942511a2461f3791da5ede32777062 | Form/editor values excluded from implicit/external labels; six-arg resolver retained. |
| STATUS | 1530f23019ae314be3a3f79f7cd5873af39da6f7 | Strict recoverable v1 status schema; terminal failure differs from query failure. |
| REDACT | 9f752a56335a15e1662016dc6db934a79adba7b5 | Bounded shared native C ABI; encoded hex-case matching and dynamic-key collision refusal. |
| HOST | e71364364db94a6212f556aa7b5ca9efb09ac003 | Host percent-hex fix, hidden Windows launch, status admission recovery tests; verified private CLI bundle. |
| BACKEND | eee84a266ad0b3613de71eb930e1bf0c9ede8cb3 | Managed cleanup/ownership, public stdio version, actual managed/WebMCP worker flows; actual Lightpanda remains separate. |
| WIN | 9333ff507ec91d06d86e338b1d2d9378daca2ac5 | Corrected held-marker compositor and native workflow runtime; owner reports actual HTTP/MCP/alias/full decode. Raw intake completed:22 curated records/432 unreviewed rows; see windows-evidence-intake.md. |
| IOS | 503a553688815e4e46487263d480d47c71a7b1cf | Compiled iOS workflow/critical-frame adapters and tests; authorized hosted fallback now builds app/CLI and starts iPhone scheduling; rendezvous/cleanup failure preserved,completed iPhone/iPad runtime evidence pending. |
| ANDROID | ca498e21eb1897918d1bf7a5b0b167bdecb1fc8b | Native/JNI/public-flow tests; initial actual phone failures retained. |
| ANDROID-FIX | 80e7f7cd204142f7ca90ccbfe69d7411b3fc0d5e | Initial video admission and screenshots-only capture deadline; corrected runtime replay still required. |
| MAC | 217f29b69bd5d709d7587f97ea0441307303f1e4 | WK+CEF app/test compile and strict owner-bound adapters; no actual launch/MCP pass. |
| MAC-FIX | cf500a355eabf48239eb48d139d995cece34e8e1 | Screenshots-only deadline enforcement; no inherited runtime pass. |
| LINUX | 90eb6830eab0e92ca224123f55748e97ed44dce1 | Actual sandboxed CEF OSR HTTP capture/extraction;8 artifacts, GIF/MP4 each13 decoded frames per owner. |
| LINUX-INTEGRATED | 33d0a80f2c4a2bf064f00c2535aaea39b6e3439b | Landed Linux media/store/sandbox/corpus source and evidence documentation. |
| QA | 4d97292f6165066fcece7d8fdee9e36a9f4c0d9d | Strict DIF normalization,9-runtime ingestion, independent artifact hashes; never automatic acceptance. |
| REGISTRY | 2078d03ee1a8b7703c56023d3a505f2df69843fb /8b7f80a87dc296b53e6f30f3fc96ec80cd3bfabf | Exact iOS/Android profiles;086d6070 trusted Mac/Linux runtime-mode projection landed and portable noCEF/noLLM four native checks passed. Mac app/profile relink also passed; actual runtime remains separate. |

Historical source checkpoints remain documented in observations.md,workflows.md,
workflow-review.md,backend-review.md,windows-codec-review.md and
windows-runtime-review.md. Closed historical findings below are not reopened by
an older checklist. Integrated merge hashes may differ from original scoped
commits; actual execution always records the exercised source and binary.

## Durable eval groups

- OBS: shared browser-observations/browser-control.browser tests; generated
  native gateway tests; tests/windows/run-observation-acceptance.mjs.
- WFL/TARGET: shared script-workflow/script-status/script-target tests,
  tests/capture/target-regressions.test.mjs; native script/gateway admission tests.
- SECRET: CLI script-secrets/script-admission tests, native/core-automation
  test_script_redaction, Apple redaction tests and Android JNI contract tests.
- MANAGED/WEB: shared managed-session/cleanup/webmcp tests; permanent production
  tests/native/worker-stdio-acceptance.mjs and webmcp-acceptance.mjs.
- NATIVE: tests/windows/run-script-capture-acceptance.mjs and alias/OBS corpora;
  iOS XCUITests; Android ScriptPublic/Security/ObservationFlow instrumentation;
  Mac XCTest sources; tests/linux native-sandbox/native-capture/marker corpora.
- MEDIA: platform codec/prefix tests plus tests/capture/verify-native-media.mjs;
  actual final all-frame marker/document and hash reports remain distinct from
  numeric/vector/codec-only tests.
- DIF: tests/capture/differential.test.mjs,native-coverage.test.mjs,harness.test.mjs.
  The9-runtime matrix preserves failure and UI/media/source distinctions.

## Requirement-to-source map

Paths are repository-relative; native adapters below denote their owned platform
counterparts, not duplicate portable algorithms. Remaining checks are finite in
outstanding-gates.md; a listed actual subset does not close an entire platform.

| ID | Landed source / symbol | Durable eval / current evidence boundary |
|---|---|---|
| OBS-01 | browser-control/snapshot.ts,dom-reader.ts; collectBrowserSnapshot | OBS private canaries; Windows OBS actual reported; other native corpus pending. |
| OBS-02 | BrowserSnapshotOptionsSchema scope/prioritize; canonical fixed reader | OBS scoped priority; no per-platform reimplementation. |
| OBS-03 | Shared walk/text/style/ancestor/copy budgets | Large/deep real Chromium passed; native bounds corpus still per runtime. |
| EXT-01 | observations.ts collectBrowserExtraction typed sources/statuses | Missing/ambiguous/incomplete tests; private Android observer targeting fixed in fc1. |
| EXT-02 | Bounded nested fields/records and shared record/field budgets | Shared nested tests; native extraction ordering/corpus still reviewed separately. |
| EXT-03 | Publisher metadata/JSON-LD allowlists and bounded parsing | OBS metadata/privacy tests; publisher claim remains untrusted. |
| EXT-04 | Raw source-order indices,provenanceComplete,matchesLimited | OBS-FIX closes filtered index source defect; actual provenance differs from revision availability. |
| RDY-01 | collectBrowserPageStatus; explicit unavailable diagnostics | DOM facts never become complete network/error evidence; native diagnostics capability-dependent. |
| RDY-02 | collectBrowserReadiness; platform wait-ready/assert loops | Shared defaults/timeout tests; actual delayed/abort/recovery per native runtime. |
| OWN-01 | managed-session.ts; CLI automation-sessions.ts; cleanup.ts | BACKEND closes failed-allocation cleanup ownership; actual production stdio proof exists. Native supplied sessionId refuses, no parallel allocator. |
| OWN-02 | Existing authenticated owner/listener/socket grants; native lease/retirement | Native platform guards and pinned CLI transport landed; actual foreign/revocation/late callback cases remain per report. |
| WFL-01 | scriptV1Schema/generated validate_script; all native strict adapters | Preflight/unknown fields/session refusal tests; native runtime subsets must be documented. |
| WFL-02 | bindScriptInputs; host secret refs; shared C ABI redactor | REDACT/HOST fix encoded variants; actual native secret and capture-refusal reports required. |
| WFL-03 | Native Windows/Linux DesktopScriptActions; IOSWorkflowActions; Android ScriptActions; Mac ScriptWorkflowActions | Ready/assert/output/extract runtime dispatch landed, not schemas only; actual ordering/readers per platform pending. |
| WFL-04 | Native versioned routing beside original legacy handlers | Host recovery tests; native legacy-busy -> v1 marker automatic recovery must be observed. |
| WFL-05 | Shared target token/focus fences and native cancellation/retirement | No uncertain retry; abort/timeout/finalizing/next-run tests live in platform corpora. |
| TGT-01 | script-target.ts role/name/label/CSS; LABEL fix | Shared real DOM label fill/type passed; Windows actual label/Enter reported. |
| TGT-02 | visibleBox,hit-test center and exact-target recheck | Windows/Linux actual trusted center reports; other native geometry remains separate. |
| TGT-03 | Shared clipping/viewport fence; native CSS-to-display mapping | DPR/zoom/scroll/pinch corpus open; visualViewport versus layout viewport needs actual iOS case. |
| TGT-04 | Same DOM object/document/geometry and focus mutation fences | Shared races and Windows actual focus refusal; no stale-token replay. |
| TGT-05 | Declared synthetic versus trusted input guarantees | Windows/Linux trusted-coordinate; Apple/Android synthetic-coordinate. DIF retains explicit difference. |
| PTR-01 | script-presentation.ts + core-automation numerical C ABI | Numeric parity passed; actual decoded C/S trajectory evidence per runtime. |
| PTR-02 | Eased shared pointer model reused by native adapters | Literal ease-in-out has numeric implementation; timing/display correspondence still reviewed. |
| VIS-01 | Shared tap model + platform drawing/compositors | Configured color/radius and fade alpha; c852 missing-pixel failure retained,9333 pixel correction reported. |
| VIS-02 | Configured wobble/fade/duration timeline and held progress0 | Metadata ACK is insufficient; movies-only fps1 all-frame pixel gate required. |
| CAP-01 | Native sampler/capture services on all five platforms | Continuous runtime source landed; actual evidence is partial by runtime. |
| CAP-02 | Native GIF writers/streamed frame staging | Codec vectors plus real GIF full decode; source marker pixels require actual report. |
| CAP-03 | Native H264/MP4 writers,sinks and commit ACKs | Windows/Linux actual MP4 decode reported; Apple/Android guards and native final replay remain required. |
| CAP-04 | Native step scheduling,PNG compositor and artifact store | PNG success never substitutes for movie marker evidence. |
| CAP-05 | Native document/viewport stamps and resize refusal | Async old/new document all-frame checks; actual each renderer still required. |
| CAP-06 | Shared capture schema + native duration/FPS/byte budgets | Screenshots-only deadlines fixed MAC-FIX/ANDROID-FIX; native measured bounds pending where not reported. |
| CAP-07 | Native backpressure,typed committed-prefix ACKs,bounded queues | Windows raw-progress bug fixed separately; Android PTS/document association fixed after review. |
| CAP-08 | Native partial finalization,sibling retention and recovery | Codec failure tests supplement actual abort/limit/next-run flows; no implicit success from playable partial. |
| ART-01 | Native opaque-ID artifact services + pinned CLI download | Windows alias/public chunks reported; other public transports still per-runtime evidence. |
| ART-02 | Existing owner/grant/listener checks in each artifact/status route | Foreign owner/revocation tests exist; actual results must be ingested. |
| ART-03 | Bounded chunks/exact socket,private exclusive files,path/handle checks | Host transfer tests and native stores landed; no device path becomes transport locator. |
| ART-04 | SHA-256,dimensions,timing,document/partial manifests | Windows39 copied/hash/decode lineage ingested without acceptance; Linux8 hashed/decoded artifacts reported. Full direct/generic chunk parity still requires the new large-PNG helper. |
| SEC-01 | Value-free reader + host/native structural secret scrubbers | REDACT/HOST closed matcher defects; actual encoded/Unicode/dynamic-key tests remain per native build. |
| SEC-02 | Fixed generated readers/targets,no arbitrary v1 eval; private grants | Native hostile-page/authority cases and WebMCP uncertainty remain separately scoped. |
| DIF-01 | Strict normalization.mjs/assertions + native-coverage.mjs | All48×9 cells unreviewed; source/unit never promoted; public ingestion command verified. |
| LP-01 | Restricted lightpanda.ts capability profile and fixed readers | Four actual pinned1.0.2 diagnostic stages ran under bounded unit/egress; corrected snapshot assertion still needed. Owner now reports7/7 public stdio at9a301405 with8 navigation/lifecycle methods,41 calls; report independently hashed/intaken as documented in lightpanda-public-intake.md. No reader/visual/input admission. |
| LP-02 | Operator-only worker config,owned sessions,cleanup and egress policy | Managed Chromium production proof exists; restricted actual LP lifecycle/egress proof does not. |
| WEB-01 | Managed canonical discover/call,private world,actual API probe | BACKEND actual Chromium151 API/public stdio passed; native defaults remain off. |
| WEB-02 | Session/origin/document grants,bounded JSON,uncertainty fence | BACKEND fixes reviewed/tested; no native grant/API/timeout support inferred. |
| DOC-01 | Common API/CLI/platform docs,recipes,generated schemas | Current mapping replaces initial schema-only claims; final docs must match actual enabled capabilities. |
| UI-01 | Native presentation/Stop controls and standard app instrumentation | Android phone Stop and Windows Session1 UIA Stop reported actual; hosted XCUITest/Compose/accessibility are authorized. Other UI/runtime cells still need their own executed outcomes. CUA/OS input remains off. |
| REL-01 | One integrated PR,required checks,component manifests/releases | Coordinator-owned; private candidates are not releases. |
| REL-02 | Published artifacts/signatures/download hashes/installed flows | Pending every affected component,including npm and platform packages. |

## Review and evidence links

- observations.md,target-labels.md,cli-common.md and backend-review.md retain
  exact common fixes,tests and prior failures.
- mobile-source-review.md and movie-admission-review.md preserve concrete
  findings and distinguish accepted metadata from visible/encoded pixels.
- windows.md,ios.md,android.md,macos.md,linux.md contain owner-reported outcomes;
  raw intake and independent review still control actual acceptance.
- resources.md records workload and access history; current scoped standard
  XCTest/Compose authorization is not CUA/VNC/arbitrary OS-input authorization.
- outstanding-gates.md lists remaining requirement/runtime closures before the
  coordinator's single final PR/release. Nothing here auto-approves432 cells.
