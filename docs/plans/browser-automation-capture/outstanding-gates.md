# Finite outstanding gates before PR and release

Snapshot: reviewed root5f4c4fcb plus common cbce8f97 and explicitly labelled later owner reports
received by the common reviewer. This is a closure list, not432 auto-approvals.
Every close records exact exercised source,target binary/version,protocol,
artifacts/hashes and actual outcome. Historical failing runs remain immutable.
Source mapping is in implementation-map.md.

| Gate | IDs | Runtime / owner | Concrete closure |
|---|---|---|---|
| G01 Registry/runtime projection | DOC-01,WFL-01,OWN-02 | Mac WK/CEF,Linux GTK/OSR; common+owners | Finish trusted runtime_mode windowed/offscreen seam and focused core tests; owners relink. Mac UI-only; Linux offscreen machine path only. Unknown mode and model/body capability forgery refuse; noCEF routes stay absent. Exact086d portable noCEF/noLLM registry/gateway/extensions/desktop MCP tests now4/4 pass on authorized local Minis fallback. Shipping relinks/runtime proof remain open. |
| G02 Windows raw intake | OBS-01..03,EXT-01..04,RDY-01..02,WFL-01..05,TGT-01..05,VIS-01..02,CAP-01..08,ART-01..04,SEC-01..02,DIF-01 | Windows9333 /common+Windows | Intake complete for native29+security3+actions1+preflight1,OBS10,alias4 reports and39 copied artifacts; archived DLL27a474... independently rehashed. Public ingestion produced22 records/432 unreviewed rows. See windows-evidence-intake.md. New f188 intake independently matched37 media/decode identities and actual906882-byte PNG4chunks per HTTP/direct/generic; see windows-f188-intake.md. Remaining closure is requirement-by-requirement review,current G07 geometry/native-window UI and final release. Two f188 WGC harness attempts failed before capture;c852 failures remain historical. |
| G03 Android corrected replays | OBS-01..03,EXT-01..04,RDY-01..02,OWN-02,WFL-01..05,TGT-01..05,VIS-01..02,CAP-01..08,ART-01..04,SEC-01..02 | Android phone and tablet independently /mobile | Preserve first6-of11 and subsequent failing phone reports. Replay after fixture/preflight/startup/deadline/private-observer/PTS-document fixes; reach actual ready/extract flow. Run public HTTP,direct/generic MCP and CLI cases,all-frame lowfps marker/navigation,abort/recovery,revocation and secret vectors. Phone lowfps/Stop subset is not tablet/full-platform success. |
| G04 iOS actual simulator flow | OBS-01..03,EXT-01..04,RDY-01..02,OWN-02,WFL-01..05,TGT-01..05,PTR-01..02,VIS-01..02,CAP-01..08,ART-01..04,SEC-01..02,DIF-01,UI-01 | iPhone and iPad independently /acceptance | Authorized hosted fallback is active:2e08956f app/CLI/test build passed and iPhone17/iPadAir were selected; iPhone scheduling/container cleanup failed and iPad withheld. Use corrected nonce rendezvous to complete XCUITest/public HTTP+MCP+CLI corpus. This is not blocked on a new local user handoff. Include lowfps movies-only marker/all-frame decode,legacy recovery,late callbacks and native Stop. |
| G05 Mac actual renderer flows | Same native OBS/EXT/RDY/WFL/TGT/PTR/VIS/CAP/ART/SEC families,DIF-01,UI-01 | macOS WK and CEF independently /workflows | Hosted Mac CI run41950256231 succeeded at28426edc (build evidence only). WK/CEF app/profile relink and3 native core checks passed; hosted runtime corpus exists atb027/91ff. Execute exact hosted app and test both renderer paths through supported transports. Verify owner-bound APIs,snapshot geometry,input,codec/capture budgets,all-frame markers,Stop and subsequent run. No source/codec-only inheritance. |
| G06 Linux mode/protocol coverage | Same native OBS/EXT/RDY/WFL/TGT/PTR/VIS/CAP/ART/SEC families,DIF-01 | Linux OSR and GTK independently /desktop_backend | Preserve actual90eb sandbox/HTTP6-action8-artifact/13-frame proof. After trusted mode assignment,verify direct/generic MCP discovery and public CLI,all-frame marker proof,deadline/abort/revocation and noCEF absence. GTK visible/native Stop requires its own authorized evidence; OSR must not claim local UI. |
| G07 Bounds and viewport geometry | OBS-03,EXT-02..04,RDY-02,TGT-02..04,SEC-01,DIF-01 | Every native renderer/device class | Apply large/deep/private/partial-provenance corpus and DPR/zoom/scroll/clipping races. Shared G07 actual Chromium CDP scale2 reproduced and corrected layout-only clipping/token defects; see visual-viewport-targets.md. Actual iOS nonzero-offset pinch/overlay fixture3aaa8d58 still needs hosted execution; do not inherit native geometry correctness from Chromium. Retain missing/ambiguous/incomplete semantics. |
| G08 Pointer and pixel timelines | PTR-01..02,VIS-01..02,CAP-01..07,DIF-01 | Every native capture runtime | Inspect sampled early/middle/late decoded C/S path,ease,wobble/fade,color/radius and actual center/document. Held admission metadata alone is insufficient. Dwell remains separate from configured duration; screenshots-only/no capture avoid movie dwell. |
| G09 Owner and uncertain completion | OWN-02,WFL-05,ART-02,SEC-02,RDY-02 | Every native runtime +managed workers | Validate foreign/revoked/rotated/listener grants,provided native sessionId zero-action refusal,late callback fence,abort/status responsiveness and next-run recovery without manual state clearing. Keep known completed earlier steps distinct from uncertain failed step. |
| G10 Managed worker and LP | OWN-01,LP-01,LP-02,DIF-01 | Backend/LP scope,not native UI /desktop_backend+root | Managed Chromium production proof already exists. Four actual pinned1.0.2 diagnostics ran under enforced unit/egress; one-context/page limit and sequential storage reset proved,prior failures retained. Owner reports7/7 public production stdio at9a301405,8 navigation/lifecycle methods and41 calls. Reportd7ca0d84... independently copied/hashed and teardown checked; close only that restricted navigation/lifecycle stage; corrected reader snapshot proof and any broader task/cost comparison remain separate. No visual/input/WebMCP inheritance. |
| G11 Optional WebMCP scope | WEB-01,WEB-02,SEC-02,DOC-01 | Managed positive path;native defaults off | Preserve actual Chromium151 private-world/grant/API/protocol evidence. Native support stays unavailable until exact trusted session/origin/document grant,API probe,encoding and completion-unknown fence land and run. A native refusal is not positive WebMCP evidence; final docs must state implemented scope. |
| G12 Status and action subset | WFL-01..04,RDY-02,DOC-01 | Every native runtime | Parse actual safe v1 status,failed/aborted partial artifact recovery,legacy-busy automatic admission recovery and no outputs/secrets in status. Verify the documented action matrix and native preflight refusals; required fill/type behavior remains a separate gate. |
| G13 Authorized native UI evidence | UI-01,VIS-01..02 | Applicable windowed/foreground apps | CUA,VNC and arbitrary OS-input helpers remain off. Root-authorized XCUITest/Compose and scoped native accessibility instrumentation are allowed under handoff/resource grants. Android phone Stop and Windows Session1 standard UIA Stop/partial/recovery/teardown (4ec) actual subsets are reported. Authorized hosted fallback removes the blanket local handoff dependency; remaining per-device scheduling/runtime and changed-state evidence still need explicit outcomes. No offscreen local Stop claim. |
| G14 Integrated proof/docs | DOC-01,DIF-01,all48 ID audit | Root+common | Integrate every worker history; run required final shared/CLI/native/platform checks on final source; review precise9-runtime evidence and remaining limits. Preserve typed input-guarantee differences. No blanket acceptance from ingestion or codec build. |
| G16 Late-sensitive privacy | SEC-01,ART-01..02,WFL-05 | Every native consumer | Shared6ad/2a fixed helper and core checks passed; Windows f188 focus-autocomplete/type actual failures are preserved. Final adapters must consume classification before guard/ticket retirement; uncertain no-result target inspection registers current edit text even without capture; capture media is discarded. Current active downloads refuse ARTIFACT_NOT_READY, foreign NOT_FOUND; final scrub precedes terminal exposure. Actual fixed platform raw/URI/form and no-result replays remain pending. |
| G15 Publish/install | REL-01,REL-02 | All affected components /root+platform owners | Bump each component's own manifest; one final integrated PR with required checks,then coordinated publication. Verify npm provenance/version/installed worker,Windows signed EXE/DLL/installer+timestamp and installed exact package,Apple signing/distribution/installation,Android signed APK/AAB phone/tablet install,and Linux DEB/RPM supported installs. Use immutable published hashes and fresh date tag; private candidates are not releases. |

The CI/PR screenshot requirement applies only to materially changed rendered
states,with matched base/final viewport/theme where applicable. Standard app
instrumentation authorization does not permit unrelated desktop input or turn
an exported frame into a local UI observation. Release/source gates are mandatory
even where a runtime-specific optional capability is correctly unavailable.

## Resource correction

A common -j1 native build incorrectly proceeded after printed preflight CPU85–87%
and free8,563,060KiB. Only its verified CMake24396/MSBuild49276 tree was stopped;
runtime-profiles-build.log is preserved. Registry compilation completed but the
full requested build/tests did not; no pass is claimed. The corrected ignored
Node launcher throws before child creation unless two fresh CPU samples are<65
and available memory is>=10GiB. Harmless CPU-denied and memory-denied tests both
proved no child marker,plus a harmless allowed-branch check. No host execution
policy was changed. Native compilation remains deferred until that real gate
permits it; Android's reserved runtime is not interrupted. Root authorized a fresh
local Minis test mirror at exact086d6070 for core/stub checks only. Existing VS18/
CMake4 toolchain was found; initial configure hit a quoted-policy-flag issue,
not a source failure. Corrected reruns were blocked before child creation by
fresh local load. Later fresh guards permitted configure/build at CPU29/49% and41/50%, with more than22GiB available. Exact086d noCEF/noLLM four-target build succeeded; CTest4/4 passed2.13s at CPU53/33% free22,993,996KiB. See runtime-profiles.md for exact commands and scope. No shipping native runtime acceptance follows from this stub check.

## Later coordinator snapshot — 2026-11-05

The coordinator identifies integration revision `4592d4a4` as the current
snapshot for this supplement. The rows below update the working status; the
older rows and their failures remain historical evidence at their own revisions.
No row grants a whole-platform or 432-cell pass.

- **Windows:** all four C/S GIF/MP4 G08 exports passed on the reported
  `5877` runtime with the `775384d7` oracle. Final native WGC and
  start/stop verification remain open.
- **Linux:** the reported pump candidate passed 36 native checks and its
  supplements. The coordinator viewed and hashed the `0d3d` Wayland After
  image (`e538...`; receipt `0b1579...`): a 1280×900 native window with
  the overlay and Stop visible. RPM install and complete G08 evidence remain
  open. The marker/pointer overlap controls do not justify a blanket pixel
  tolerance; preserve the earlier GIF and MP4 failures.
- **Mac:** full runtime run `42006708868` remains a gate; WK and CEF need
  separately reviewed outcomes.
- **iOS:** diagnostic run `42006716721` remains a gate; iPhone and iPad
  need separately reviewed outcomes.
- **Android:** final-source native scene, privacy and full phone/tablet acceptance
  remain gates; earlier partial results are not full acceptance. The user approved
  Android 10 (API 29) as the minimum supported OS on 5 November 2026.
- **Shared and delivery:** five persistent-token CLI tests timed out in the
  full run and again in an initial serial three-file retry. A later unchanged
  serial rerun passed all 12 cases; instrumented copies also passed, so the
  earlier timeouts remain unexplained. A clean full pnpm test at
  d854c65a passed shared 143 tests and CLI 703 tests with one skipped;
  the final integrated revision still needs its own required checks.
  Final component versions, the single PR, required checks, release
  publication and installed-release verification remain open.

Run identifiers identify evidence to inspect, not a claim that the run passed.
The coordinator must reconcile newer results and exact artifact hashes before
closing any requirement.

## Current scope supplement - 2026-11-05

Source snapshot `d7f4306d`. Reports below identify the source, test or
hosted run actually exercised; earlier rows and platform receipts preserve
historical failures. No row claims whole-platform acceptance.

- **Shared and release:** the 52-case mutation-receipt matrix passed Android,
  iOS and Mac production decoders and validators. This is not full native
  workflow proof. Final integrated portable checks, component versions, the
  single PR, required CI, signing, publication and installed-release checks
  remain open. Lightpanda 1.0.2's explicitly selected DOM/text reader passed
  its 16-case public stdio corpus; published-package verification is open.
- **Default pointer speed:** the shared schema and desktop, Android, iOS and
  Mac fallback sites specify 350 ms when the pointer is enabled and duration
  omitted. Explicit overrides remain supported; dense G08 intentionally uses
  2400 ms. Windows `de318b47` omitted-duration C recorded five intermediate
  samples and a 383.34 ms observed endpoint bracket. A separate analysis with
  shared fitter `131031d5` measured 350/500 RMS fits of 6.00/90.47 CSS px;
  output SHA-256 `6e7d98efaf75836d7158d4211ff856e0d281684aa26c0c040854189a05164bb2`.
  This is scoped native evidence, not exact
  timing or display/export parity. Linux `80644c78` omitted C/S produced
  insufficient samples in all four GIF/MP4 fits, with 201 sampler drops per
  run. Mac's omitted-default case did not pass in `42091168804`; current
  hosted verification is pending. iPhone, iPad, Android phone and tablet
  need final-source omission and capture-disabled isolation evidence.
- **Windows:** Session 1 native CTest passed 65/65. Dense C/S at `de318b47`
  passed path/easing analysis but both stopped at marker-onset opacity.
  An owned known-opacity WGC control showed BGRA [0,0,178,178] retained
  unchanged while metadata labelled it straight; treating those bytes as
  straight produced RGB [201,77,77], while premultiplied composition produced
  [255,77,77]. The scoped alpha-observation correction `664bb462f8a9642d35ec50111da99b5fd2cd3a62` has not
  yet received a corrected native replay. Do not convert the prior dense
  failures into passes. Final C/S native/export comparison and signed
  installed-package checks remain open.
- **Linux:** installed runs with 256 MiB shared memory cleared the prior
  Ubuntu and Fedora navigation failures; earlier 64 MiB diagnostic samples
  and failures remain preserved. Ubuntu hosted `42092291516`, source
  `80644c78`, passed 54/54 native checks in original and untraced replay,
  then both failed media verification: MP4 manifest count 15, decoded count
  14. The retained original MP4 SHA-256 is
  `df7a97cf8a9633f74a5906f9c63ec74b14549bd7abf1c30496a052fc2df24e4f`.
  Both final VCL samples physically exist; the last trun lacks an explicit
  offset and ffprobe identifies its position as the moof base. The qtmux
  implicit-run versus FFmpeg interpretation is the current finding, not a
  validated mux fix. The separate immediate-end marker-tail failures remain
  open; an instrumented `4bab` expired source sample and both encoded tails
  were clear, but do not explain earlier nonzero tails.
- **Android:** API 29 minimum is approved. On API 35 phone and tablet,
  `fb2` app and `b685` tests passed native marker and actual Stop,
  partial-result and recovery flows. Conversion change `11384080` passed
  two native codec controls and reduced C/S conversion from 72.2/70.6 to
  55.8/51.9 ms per frame. Dense C/S in all formats remained insufficient at
  roughly 100 frames over 28 seconds. Same-phone anchored-cadence changes
  `1184b44f`/`2d9aa7c5`, integrated at `c1e63a6a`, produced 108/108
  C/S frames versus 100/102 and MP4 median gaps near 258 ms versus 278/274;
  dense evidence remains insufficient and short timing has not started.
  Full device corpora, omitted-default
  and capture-disabled proof, inference cancellation and signed final-source
  replay remain separate gates; see `android.md`.
- **macOS:** WK run `42091168804` at `9f366` passed semantic, privacy,
  Stop, low-FPS and CLI GIF/MP4/PNG checks. Its omitted-350 case failed with
  generic assertion and G08 was not reached; CEF switch failed at DNS
  listener setup and CEF was not exercised. Earlier `42081421741` passed
  WK dense C MP4/GIF and S GIF, with S MP4 insufficient. The current
  `42095244866` includes source fixes and is still running; no pass is
  inferred from it.
- **iOS:** completed `42088321625` at `0850bde7` passed 3/8 on each
  device. Both failed normal and interaction-disabled keyboard controls;
  iPhone also failed live projection and two capture admissions, and iPad
  failed both pinch controls and MCP marker. Same-scene iPhone evidence
  measured CSS (175,340) and native (175,402), with top/bottom insets 62/34;
  iPad centers matched with insets 0/20. Focused geometry run `42095635452`
  and DEBUG callback probe `42096878949` are pending device outcomes.
  Projection, pinch, omitted-default, both public device corpora and release
  verification remain open.

## Later evidence checkpoint - 2026-11-05

Integration `417641154c72fcc75730458589490269dd001dd8`; each result
below retains its own product and test revision. Earlier failures are not
reclassified, and these checkpoints do not establish platform acceptance.

- **Windows:** omitted-duration C live pointer evidence remains as previously
  recorded. For product `54c` (binary SHA-256 begins `c0311849`) and
  harness `1ec35e15`, the Maxis split diagnostic recorded 227 samples,
  two outputs per action and cleanup. Median pre-navigation, pre-work,
  screenshot, post-navigation, post-viewport and encoder times were 0.245,
  1.103, 27.081, 47.045, 1.127 and 5.642 ms. Diagnostic SHA-256:
  `c59c8c22a8c561667bf642bfc6b18303dd58c2131dc750b76c15ceb7ea10e3e0`.
  This is not a dense export pass.
- **Linux:** Ubuntu installed source
  `1a148927ad081fab54a71ba8ada95bf038c7c9ef`, test source
  `45d841a5535123a6b3ff176e57aeded6cd014b43`, run `42107002688`,
  passed 54 native cases, decoded 44 artifacts, passed the continuous-marker
  check and five public CLI checks with ten observations, and cleaned up.
  See [Linux evidence](linux.md); this does not prove a published install or
  physical desktop. Fedora run `42102220654` decoded both 15/15-frame MP4
  streams, but final marker analysis retained 2/11 red-classified pixels;
  same-frame source attribution is unavailable.
- **macOS:** WK `421018`/`c102` passed one combined fast case with seven
  samples and a 70 ms maximum gap. In rerun `421059`/`16c3`, both WK
  fast cases were insufficient and CEF failed its edge check before timing;
  report SHA-256 begins `6e89d59e`. Focused hosted run `42110244904`
  at `41764115`, with immutable step-PNG and final live-marker candidate,
  is pending; source alone is not a pass.
- **iOS:** geometry `421062`/`dd53` passed 5/7 on each device, including
  three units and live center. iPhone scrollable pinch passed; the original
  pinch target was fully outside its fixture and paired navigation returned
  `NAVIGATION_BUSY`. iPad paired MCP and decode passed, but both pinch
  scales remained 1. Keyboard `421038`/`d0a7` returned
  `CAPTURE_VIEWPORT_CHANGED` on both devices after only the first input:
  iPhone observed zoom 1.455 and offset, iPad an owned keyboard frame. No
  safe production exception is established. Marker candidate
  `42110055424`/`f2a8a255` is pending.
- **Android:** same-device no-capture host recording measured an omitted
  duration span of 369 ms with 350/500 fits 10.88/34.31 px, and explicit
  500 ms span of 442 ms with fits 13.62/13.02 px. Both failed the strict
  9 px fit criterion. No product clock change or console replay is inferred.

Final per-platform formats, privacy, Stop and recovery, the integrated PR,
release publication and actual installed-artifact checks remain open.

For the later evidence checkpoint, see [acceptance checkpoint at 48c7a7c8](acceptance-checkpoint-48c7.md).
