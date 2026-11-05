# Acceptance ledger

Status: implementation and real-device evidence pending. This ledger does not certify a release.
The [landed implementation map](implementation-map.md) links canonical IDs to exact source symbols, durable evals, reviewed source checkpoints and remaining native evidence.
Base reviewed: `b6784ff723b27da4096fdd8d9227f2a00dfc9084`.
Owner: common contracts/CLI and acceptance (/observations).
Source worktree: Maxis `D:/Worktrees/kelpie/capture-observations-20261104`.
The former QA worktree remains read-only; iOS implementation now belongs to /acceptance.
See [architecture review](architecture-review.md), [resource ledger](resources.md),
[independent mobile source review](mobile-source-review.md),
and [fixture instructions](../../../tests/capture/README.md).

## Gates and evidence

The latest user direction authorizes parallel implementation by per-platform owners;
the earlier Windows-first execution gate is historical and no longer blocks other
platform source work. Resource slots still come from the coordinator. Computer Use,
VNC, CUA and custom OS/desktop-input helpers remain explicitly off. Root-authorized
standard XCUITest/Compose and scoped native accessibility instrumentation
(Windows UIA/Linux AT-SPI where authorized) may exercise native app controls and
capture app screenshots under its assigned simulator/emulator handoff and resource
slot; that authorization does not grant arbitrary desktop control.
Machine-interface evidence and native UI evidence must remain distinct.
Each renderer must be named: macOS WebKit and Chromium are
separate cells; iPhone/iPad, Android phone/tablet, Windows CEF and Linux CEF are
separate cells. Linux GTK and Linux CEF offscreen/OSR are distinct runtime cells;
noCEF stub and external workers remain separate evidence. See
[differential ingestion](differential-evidence.md) and
[critical movie admission review](movie-admission-review.md).
A platform without the capability must return a documented
unsupported response; that refusal does not satisfy required native parity.

Every row below starts **pending**. To close it, append an evidence record to the
run report with: requirement ID; exact implementation path/symbol; exact test
command and test name; full source SHA; installed version and binary SHA-256;
host/OS/device/renderer; real HTTP/MCP/CLI request entry point; steps taken;
observed result; artifact paths and SHA-256; reviewer and UTC time; status
passed/failed/blocked. A blocked record names the concrete blocker. Automated
assertions and manual media inspection are separate evidence. Missing evidence
cannot become a pass or an omitted requirement.

Machine-readable reports use `tests/capture/evidence.mjs`. Generated reports,
video, images, credentials and logs belong in ignored build artifacts, not Git.
The fixture canaries are synthetic; authentication material must never enter
reports. Store only a stable non-secret session label.

## Requirement matrix

Platform key: N = every native platform/renderer above; B = Playwright browser;
L = restricted Lightpanda; T = transport/CLI; P = published installed artifacts.
"Code owner" maps the requirement to the implementation tranche until exact paths
and symbols exist. Every implementation owner must replace this with landed paths.

| ID | Requirement and invariant | Code owner | Durable eval / fixture | Real user flow and expected result | Scope |
|---|---|---|---|---|---|
| OBS-01 | Value-free observation excludes values, editors and private accessible names | observations | private form canaries; inherited editor label | Snapshot fixture; no private canary in response | N B L |
| OBS-02 | Scoped snapshot excludes sibling regions; priority retains actions/headings under bounds | observations | catalogue scope + low budgets | Observe scoped catalogue twice; stable order, no unrelated controls | N B L |
| OBS-03 | Snapshot bounds cover text, elements, names and metadata; truncation truthful | observations | oversized text and names | Tighten limits; bounded response and explicit truncation | N B L |
| EXT-01 | Deterministic scalar extraction, missing/ambiguity and allowlisted sources | observations | catalogue text/href, duplicate/missing selector | Extract exact values; duplicates cannot silently select first | N B L |
| EXT-02 | Nested records and repeated rows retain structure and deterministic order | observations | two catalogue articles with nested fields | Extract products; two distinct ordered records | N B L |
| EXT-03 | Publisher metadata and allowlisted JSON-LD fields, bounded recursion | observations | Product/Offer + forbidden JSON-LD canary | Extract supported metadata; unknown field absent | N B L |
| EXT-04 | Extraction provenance identifies document, source selector/type and truncation | observations | navigate between extraction calls | Compare results; correct document and source attribution | N B L |
| RDY-01 | Status reports DOM facts and diagnostic availability honestly | observations | complete DOM with delayed task | Status may be complete while task loading; unknown network/errors explicit | N B L |
| RDY-02 | Readiness is explicit immediate predicate; unique visible selector required | observations | delayed/failed task and duplicates | Poll specified predicate; ambiguity/hidden/failure cannot report ready | N B L |
| OWN-01 | Session context/page isolation and per-call owner authorization | desktop_backend | two authenticated owners | Owner B cannot observe/mutate/close A context | B L T |
| OWN-02 | Existing socket serialization, ref generation and durable pins preserved | all | parallel calls, stale ref, late callback | No cross-tab ref use; uncertain mutation reconciled without retry | N B T |
| WFL-01 | Strict versioned workflow with bounded steps and unknown-key rejection | workflows | malformed version/keys/nonfinite/huge fields | Public play-script route rejects before dispatch | N T |
| WFL-02 | Reusable typed input/secret refs do not interpolate executable scripts | workflows | inputs, missing/type-wrong/secret refs | Same workflow runs with new inputs; bad refs fail early | N T |
| WFL-03 | Assertions/extractions and explicit readiness waits run in order | workflows | delayed catalogue task | Successful assertion proceeds; failed assertion stops subsequent mutation | N T |
| WFL-04 | Legacy play-script compatible without widening privilege | workflows/native | valid old script + invalid mixed shape | Old client works; v1 cannot bypass strict checks via legacy fallback | N T |
| WFL-05 | Uncertain mutation halts with mayHaveCompleted; no automatic replay | workflows/native | late action callback | Observe result; one click only; queue recovers when ownership retires | N T |
| TGT-01 | Semantic role/name resolves exactly one visible enabled target | workflows/native | unique/duplicate/hidden/disabled buttons | Confirm clicks once; other cases refuse | N |
| TGT-02 | Coordinate is visible target center and hit-tested | workflows/native | covered button, scroll target | Cover blocks action; uncover then correct center receives it | N |
| TGT-03 | Center remains correct with scroll, DPR, zoom and viewport clipping | workflows/native | event geometry + viewport variants | Inspect click coordinate against current visible bounds | N |
| TGT-04 | Object/document/geometry rechecked after presentation | workflows/native | moving target, replace button, navigation | No stale click; coherent re-resolution or explicit refusal | N |
| TGT-05 | Advertised input guarantee matches event trust | native | fixture event.isTrusted | Record synthetic vs trusted honestly for each renderer | N |
| PTR-01 | Optional C and S paths are nonlinear with exact endpoints and ease-in/out | workflows/native | sampled pointer positions/timestamps | Play both curves; smooth visible travel arrives at target | N |
| PTR-02 | Deterministic numeric motion model matches native display and composited media | workflows/native | same seed/options + frame timestamps | Compare displayed pointer to exported frames | N |
| VIS-01 | Configured color/radius and fade alpha timeline produce requested marker pixels | workflows/native | contrasting palette and white fixture | Inspect PNG/GIF/MP4; correct center and color | N |
| VIS-02 | Wobble and fade change over time and end cleanly | workflows/native | early/middle/late decoded frames | Observe wobble then fade; no stuck overlay | N |
| CAP-01 | Script emits real animated GIF, playable MP4 and per-step PNGs | native/workflows | header + decode + playback | Download exports and open all; animation and every step visible | N T |
| CAP-02 | GIF has valid loop count, frame count/delays and fixed dimensions | native | decoded GIF metadata | Play repeated loop; elapsed duration matches timeline tolerance | N |
| CAP-03 | MP4 decodes, has monotonic timestamps, correct duration/dimensions | native | ffprobe or platform decoder | Play start/middle/end; no blank/corrupt frames | N |
| CAP-04 | Every step screenshot includes intended visual overlay at capture time | native | manifest step indices + decoded pixels | Inspect each screenshot; no missing or post-fade marker | N |
| CAP-05 | Screenshot/frame and overlay share document+viewport generation | native | navigate mid-run, resize during frame | No old coordinates on new document; resize returns partial explicit error | N |
| CAP-06 | Duration/FPS/width/bytes/steps bounded before resource admission | native/workflows | limits and invalid ranges | Oversized request rejected; runtime bounds stop with truthful partial output | N T |
| CAP-07 | Encoder backpressure bounded, dropped frames counted, real time preserved | native | throttled encoder | No unbounded queue; playback duration correct despite drops | N |
| CAP-08 | Cancellation/failure finalizes partial output and self-recovers | native/workflows | abort encoding, failed step, next run | Stop through public path; retrieve partial result; next run works | N T |
| ART-01 | Remote clients retrieve bytes by run/artifact ID, no inaccessible temp paths | native/workflows | separate client chunk reassembly | CLI/MCP download across host boundary; hash/size match manifest | N T |
| ART-02 | Downloads/status/cancel enforce current auth owner and revocation | native | same/different/revoked grant, listener restart | A succeeds; B/revoked client refused; no existence/body leak | N T |
| ART-03 | Chunk integers/size/range/path traversal and unbounded reads rejected | native/workflows | malformed ID/range/length and concurrent requests | Strict errors, bounded response, no filesystem access | N T |
| ART-04 | Manifest identifies MIME,size,hash,partial,timing and document provenance | native/workflows | reassembled file digest | Independent hash matches; partial/error never called complete | N T |
| SEC-01 | Secrets absent from structured outputs, errors, logs and manifests | all | secret input refs and canaries | Review redacted response/logs; no tokens/secret values | N B L T |
| SEC-02 | Page instructions/JSON-LD do not become agent authority or executable input | observations/workflows | fixture malicious instruction | Treat as untrusted text; no credentials/external action | N B L |
| DIF-01 | Shared fixture corpus compares normalized public semantics across renderers | acceptance | differential assertion | Record native and backend outputs at same fixture revision; explain differences | N B L |
| LP-01 | Restricted Lightpanda advertises only proven DOM methods | desktop_backend | capability audit | No screenshot/layout/pointer/native-input promise | L T |
| LP-02 | Unsupported capability rejected before backend dispatch; isolation retained | desktop_backend | unsupported method + owner crossover | Explicit UNSUPPORTED/authorization error; no emulation | L T |
| WEB-01 | WebMCP discovery/evaluation requires capability; unavailable is explicit | workflows/backend | feature absent/present fixtures | Absent API refuses; supported API stays scoped and bounded | N B L |
| WEB-02 | WebMCP page tools cannot enlarge authorization or leak secrets | workflows/backend | untrusted tool metadata and hostile results | No arbitrary endpoint, code or authority expansion | N B L |
| DOC-01 | Public docs and AI-facing help explain actual guarantees, limits and uncertainty | all | compare schemas/help/docs to capabilities | Follow documented CLI and MCP examples successfully | N B L T |
| UI-01 | No extra product UI; changed overlay states have base/final screenshot pairs | all | changed-state inventory only | Confirm only requested circle/pointer/recording behavior changes | N |
| REL-01 | One integrated PR, required checks and per-component version bumps | root | release/CI audit | No omitted branch or requirement; exact source revision published | P |
| REL-02 | Published signed artifacts installed and exercised; immutable date release | root/platform | hashes/signatures/install/runtime flow | Installed version performs above flows; record download/source hashes | P |

## Manual sequence

1. Confirm exact installed binary, renderer and source SHA; coordinate replacement
   of stale Kelpie instances. Open the fixture using the real browser UI.
2. Pair through the supported product path. Discover canonical methods and
   extensions through direct MCP and the CLI alias bridge. Save scrubbed catalogs.
3. Observe scoped and bounded snapshots; extract catalogue and metadata; start
   the delayed task and evaluate readiness while it is loading and after completion.
4. Execute a typed workflow through the documented CLI, then direct MCP. Choose
   the unique button semantically, show both curve shapes and configured marker
   color/wobble/fade, assert the result, extract values and export all formats.
5. Fetch every artifact from another process/host using authenticated chunks.
   Verify size/hash, decode media, play GIF and MP4, inspect all step PNGs and
   early/middle/late frames. Check current document marker in every frame.
6. Exercise duplicate/covered/moving/replaced targets, scroll/DPR/zoom, navigation,
   resize, failed readiness, assertion failure, duration/size bounds and abort.
   Run another successful workflow without clearing state by hand.
7. Try another session and revoked grant against status/cancel/download. Confirm
   stale refs, uncertain mutation and Nessie durable pins retain existing behavior.
8. Run the exact corpus independently on each native renderer under its assigned
   coordinator resource slot; other platforms do not wait for Windows acceptance.
   Restricted Lightpanda refusal evidence remains distinct from native support.

VIS-01/VIS-02/CAP-01/CAP-02/CAP-03 additionally require a movies-only low-FPS
navigation flow (including fps1) with every GIF/MP4 frame decoded. A tap marker
must appear on the correct pre-navigation document in each requested movie
format; a correct step PNG alone cannot close this gate. Pre-input held-marker
dwell is separately recorded from configured animation duration. Preserve the
FPS cap, cancellable bounds and final exact-target recheck; screenshots-only/no
capture must not inherit an unnecessary movie-admission delay.

The initial ledger author ran no flows at creation. Later source/core/headless and exported-media results are recorded in the linked implementation/review/platform ledgers; they do not automatically promote any native cell to passed. UI/Stop verification remains blocked by the user hold.

## Canonical ID crosswalk
This ledger is the sole definition of acceptance IDs. Earlier planning/checklist
IDs below are historical aliases, not additional acceptance requirements. Update
owner checklists to use canonical IDs; never mark a row complete using an older
CAP identifier with a different meaning.
| Earlier checklist ID | Canonical requirements |
|---|---|
| CAP-01 HTTP/CLI/MCP same script | WFL-01, DOC-01 |
| CAP-02 semantic target | TGT-01 through TGT-05 |
| CAP-03 tap marker | VIS-01, VIS-02 |
| CAP-04 pointer | PTR-01, PTR-02 |
| CAP-05 continuous GIF/video | CAP-01, CAP-02, CAP-03, CAP-05, CAP-06, CAP-07 |
| CAP-06 remote step screenshots | CAP-04, ART-01, ART-04 |
| CAP-07 abort/time/byte bounds | CAP-06, CAP-08, WFL-05 |
| CAP-08 scoped artifact retrieval | ART-01 through ART-04 |
| REPLAY-01 strict versioned actions | WFL-01, WFL-04 |
| REPLAY-02 typed inputs/secrets | WFL-02, SEC-01 |
| REPLAY-03 assertions/readiness | WFL-03, RDY-02 |
| REPLAY-04 structured output | WFL-03, EXT-01 through EXT-04 |
| REPLAY-05 unsupported/preflight | WFL-01, DOC-01 |
| REPLAY-06 abort/uncertainty | WFL-05, OWN-02, CAP-08 |
| OBS planning group | OBS-01 through OBS-03; extraction belongs to EXT-01 through EXT-04 |
| DIA / READY planning groups | RDY-01, RDY-02 |
| SESSION planning group | OWN-01, OWN-02, ART-02 |
| BACKEND planning group | LP-01, LP-02, DIF-01 |
| WEBMCP planning group | WEB-01, WEB-02 |
See [workflow source review](workflow-review.md) for reproduced defects at the
initial shared-contract checkpoint. Those findings remain open until fixing
revision and focused/real-renderer results are recorded.
