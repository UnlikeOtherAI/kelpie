# Integrated acceptance audit — 0c9433b9

Source reviewed: `0c9433b923b135f7053610e6326d97743cb49efc`, 5 November
2026. This is a source-and-evidence audit, not a runtime execution or release
approval. [acceptance.md](acceptance.md) remains the definition of all 48 IDs;
[reviewed-cells.md](reviewed-cells.md) contains frozen, narrowly accepted cells.
The [implementation map](implementation-map.md) supplies source anchors and
durable evals. Reports and images retain their actual source and binary identities;
neither an owner report nor this document converts unreviewed evidence to a pass.

> Scope update, 5 November 2026: the user approved Android 10 (API 29) as the
> minimum supported OS. The API 28 gap described in this frozen audit is no
> longer a supported-OS release blocker; Android runtime acceptance remains open.

## Functional gaps and scope decisions

- **Android API 28 is an implementation gap.** Android declares minSdk 28, but
  the current PixelCopy capture path explicitly fails closed there pending a
  verified frame fence. That is safer than publishing an uncertified scene,
  but it leaves walkthrough capture unavailable on a supported Android version.
  API 29+ also needs real scene, overlay, clipping and lifecycle replay; a
  successful compile or a fail-closed response does not prove captured content.
  See [Android compositor record](android.md).
- **Historical finding, resolved scope: strict keyboard action is narrower than the schema.** The shared
  v1 schema accepts `press-key`; desktop Windows/Linux preflight implements
  supported trusted-key plans. Android, iOS and macOS preflight reject this
  action. Android/iOS remain mirrored on this limitation. The public workflow
  documentation says action subsets vary, and Android's API reference names
  the refusal. The original recording catalogue requires text entry but does
  not list standalone press-key; the combined contract permits preflight
  refusal for platform subsets. Android and iOS mirror that limitation.
  Standalone press-key is therefore an intentional subset; required fill/type
  behavior and native refusal evidence remain separate runtime gates.
- **Linux cadence and codec evidence remain functional gates.** The one-CPU
  pump candidate passed S/MP4 dense export analysis, but C/GIF and C/MP4 had
  insufficient phases and S/GIF's old oracle reported a stuck marker. The
  original non-pump one/two-CPU captures retained about 60 frames and dropped
  about 250 over 15 seconds. The calibrated same-recording oracle has matched
  pointer-only versus small, faint and full overlap controls; a new actual
  candidate run must demonstrate the required dense phases and clean end.
  The coordinator approved a calibrated replay and a private copy-on-write
  bind-mount RPM retry under reviewed bounds; neither is a result yet.
  The separate 19-red-pixel MP4 failure remains open: real-encoder controls
  show that a 19-pixel allowance hides a small retained marker.
- **Scope, not missing implementation:** restricted Lightpanda publicly admits
  only its explicitly verified eight navigation/lifecycle methods; DOM readers,
  input, capture and WebMCP remain unavailable. LP-01/02 are accepted only for
  that frozen profile; multi-owner crossover and broader reader/task comparisons
  remain separate. Managed Chromium WebMCP requires an operator grant, exact origin
  and actual private-world API probe. Native/Lightpanda unavailability is not a
  positive WebMCP pass or a reason to claim native support. See
  [worker documentation](../../api/automation-workers.md) and
  [Lightpanda review](lightpanda-independent-review.md).
- Public workflow docs describe action subsets, synthetic versus trusted input,
  bounded media, privacy disposal, owner-bound artifacts, API 28 refusal and
  optional worker boundaries. These descriptions do not establish actual native
  behavior. DOC-01 still needs final-source schema/help/example reconciliation,
  including the keyboard scope decision and any later Android API 28 change.

## Nine native runtime cells

| Runtime | Actual evidence to retain | Exact work still required |
|---|---|---|
| Windows CEF windowed | Frozen f188 has 16 reviewed cells and actual 5877 G08 exports under the prior oracle. Coordinator independently viewed native overlay PNG `1a74...`, Stop image `fa68...` and rehashed report `c1adc24...`; these establish spatial/Stop subcases only. | Owner is implementing dense **native** C/S timeline and native/export correspondence. Final privacy/G07 relink, remaining semantic, owner/protocol and changed-state images need exact-source evidence. Earlier WGC/launch and c852 failures remain. |
| macOS WK | Compiled renderer and prior hosted checkpoints are source/build evidence. New run `42009261188` exercises artifact-refusal diagnostics at 0c943; its outcome must be ingested. | Full actual WK workflow, privacy/ownership, geometry, codecs, dense native/export timeline, Stop and recovery on the final binary. |
| macOS CEF | Separately compiled CEF adapter; no WK inheritance. The same new hosted diagnostic must identify its actual renderer coverage. | The same required corpus independently in CEF, including frame/presentation correspondence and owned Stop. |
| iPhone WK | Hosted run `42006716721` is still associated with old 4592 source; earlier navigation checks are bounded subcases. | Final-source public HTTP/MCP/CLI, privacy/geometry, export decode and native pointer/marker/Stop journey on iPhone. Preserve scheduling and previous failed runs. |
| iPad WK | Separate hosted device/profile; phone evidence cannot substitute. | Independent final-source corpus, including pinch/geometry, native scene, media and Stop/recovery. |
| Android phone Chromium | b927 retained the white exported PNG despite noisy live DOM, plus six failed instrumentation cases; native Stop succeeded only as a bounded older subcase. Run `42007603401` has entered the API 35 native phase. | Ingest the actual run and final PixelCopy fix outcome; prove page underlay, overlay/Stop exclusion, privacy and all media. API 28 support remains the separate implementation gap above. |
| Android tablet Chromium | b927 also had six failures and failed CLI PNG assertion; old spatial images are subcases. | Independent final-source tablet scene/geometry, pinch, public transports, artifacts, native Stop and recovery; retain old failures. |
| Linux GTK CEF | Frozen 3001 Stop/partial/recovery and manifest cells were reviewed. At 0d3d, coordinator viewed the isolated Wayland 1280×900 native overlay/Stop PNG `e538f31f...`, receipt `0b1579...`; it is a spatial image, not a physical GNOME click or dense timeline. | Final binary native C/S timeline and export comparison, changed-state image coverage, package installation, remaining owner/privacy/geometry requirements. |
| Linux OSR CEF | 0d3d native HTTP/MCP corpus passed 36 cases and supplements; pump candidate repeated that corpus and supplements. This is offscreen machine evidence, not local UI. | Approved calibrated G08 replay on final pump source, real decoded PTS/drop counts and clean-end controls, complete alias/ownership/privacy review and installed RPM/DEB gates. Preserve sparse and marker failures. |

The in-flight run IDs above are intake targets, not assertions that the runs
passed. Reconcile owner results, source hashes, binary hashes and retained
artifacts before updating any cell.

## Requirement-by-requirement closure work

All requirements below refer to the native cells above where applicable. A
frozen reviewed cell remains accepted only for its named source and scope.

| Canonical IDs | Remaining functional proof or action |
|---|---|
| OBS-01, OBS-02, OBS-03 | Real value-free snapshots, scoped ordering and bounded/truncated huge/deep inputs, including late private labels; compare each final renderer's public result and retained uncertainty. |
| EXT-01, EXT-02, EXT-03, EXT-04 | Actual scalar/missing/ambiguous and nested extraction, allowlisted metadata/JSON-LD, source/document provenance and truncation after navigation. |
| RDY-01, RDY-02 | Final native status distinguishes DOM completion from unavailable diagnostics; delayed, hidden, duplicate and failed readiness predicates refuse or resolve correctly. |
| OWN-01, OWN-02 | Multi-owner worker isolation beyond the tested Lightpanda single-session profile; native grants, pins, listener generations, stale refs and late callbacks across real HTTP/MCP/CLI. |
| WFL-01, WFL-02, WFL-03, WFL-04, WFL-05 | Strict admission and typed inputs/secrets, ordered extract/assert/readiness, legacy recovery, and single-dispatch uncertain completion/next-run recovery. Standalone press-key is an intentional subset; verify required fill/type and native refusals. |
| TGT-01, TGT-02, TGT-03, TGT-04, TGT-05 | Unique visible semantic target, hit testing, clipped/pinched/scrolled geometry and document/element recheck; record each renderer's actual trusted or synthetic event guarantee. |
| PTR-01, PTR-02 | Dense actual-PTS C/S path, endpoint and easing for each native presentation and export, with independently fitted native/export correspondence and bounded gaps. Do not infer animation from stills or held admission phase. |
| VIS-01, VIS-02 | Configured color, radius, base opacity, wobble and fade over sufficient phases and visible clean end on native and exported scenes. Same-recording calibration cannot prove an overlay wholly occluded by the pointer. |
| CAP-01, CAP-02, CAP-03, CAP-04 | Full GIF/MP4 playback, loop/delays, duration/PTS and per-step PNGs, including movies-only low-FPS navigation with every frame decoded. |
| CAP-05, CAP-06, CAP-07, CAP-08 | Document/viewport and resize fences, declared bounds, counted dropped frames with real-time playback, abort/failure partials, Stop and automatic next-run recovery. |
| ART-01, ART-02, ART-03, ART-04 | Cross-process/host authenticated chunk retrieval, independent hash/size, malformed bounds, owner/revocation/listener changes and truthful manifest/partial provenance. |
| SEC-01, SEC-02 | Raw/URI/form secret canaries and inferred-sensitive before/after input, missing/late callbacks, capture discard latch and error replacement; page instructions/metadata remain untrusted. Keep prior actual privacy failures. |
| DIF-01 | Review normalized same-fixture public observations across final native renderers and admitted worker paths; justify typed input and capability differences rather than erasing them. |
| LP-01, LP-02 | Restricted frozen public profile accepted as above; revalidate any enlarged inventory, owner crossover or new binary separately. |
| WEB-01, WEB-02 | Verify truthful unsupported native/Lightpanda responses; managed positive API/grant/origin/encoding and hostile page tool cases remain distinct from native support. |
| DOC-01, UI-01 | Final capability/schema/help/example truth and recorded keyboard/API scope; only materially changed native screens/states receive matched base/final evidence. |
| REL-01, REL-02 | Integrate every branch, bump affected versions and run final source checks before one PR; merge when required checks pass, then sign/publish exact artifacts, install and exercise those published artifacts. |

## Changed screens and delivery

Capture only the actual changed pointer/circle and recording/Stop states. Pair
base and final images by runtime, state, viewport, theme and supported device;
a genuinely new state may state that no prior equivalent exists. Existing
unchanged navigation and settings do not need images. Windows and isolated
Linux spatial evidence above are useful After candidates only for their actual
binary/source; Mac WK/CEF, iPhone/iPad and Android phone/tablet need their own
final native images. Linux OSR has no local screen. A video frame is not a native
window screenshot. The PR needs labelled Before/After cells directly in its body.

[Final UI and release actions](final-ui-release-actions.md) and
[release readiness](release-pr-readiness.md) retain the detailed version,
signing, package and install sequence. At this source, manifest versions are shared 0.1.10, CLI 0.1.22, macOS
0.1.35, iOS 0.1.21, Android 0.1.19/code 19, Linux 0.1.15 and Windows
0.1.16. Recheck current manifests and published versions immediately before
bumping; all affected components need their release versions. The Windows four version mirrors must
match; package CEF/sandbox and sign the verified copy with the existing Azure
identity. Android requires all configured signing secrets and verified APK/AAB;
Linux needs actual supported DEB/RPM installs; macOS/iOS need their declared
distribution and installed-runtime checks; shared/CLI need provenance publication.
Install and exercise the exact published hashes, including the Mac application
replacement/relaunch. A private package, passing source suite or candidate CI
is not a published installed release.

## Evidence intake

Use `tests/capture/evidence.mjs` and [differential evidence](differential-evidence.md)
for record shape, then manually review each ID against exact source, installed
version, binary hash, renderer/device, entry point, actions, timestamps, artifacts
and independent hashes. Owner ledgers are [Windows](windows-evidence-intake.md),
[Linux](linux.md), [macOS](macos.md), [iOS](ios.md) and [Android](android.md).
Keep raw reports and media in owned ignored artifact directories, with the
historical failed runs intact. The full portable test at d854c65a passed
shared 143 and CLI 703 with one skipped; final integrated checks are still open.


## Later restricted worker evidence

A later public stdio corpus at test source `0b81b975` and candidate build
`e94b059e` passed all 16 checks for the pinned Lightpanda 1.0.2 profile,
including explicitly selected fixed snapshot/extract/status/ready readers.
The default remains empty and the eight-method navigation-only profile above
describes the earlier frozen proof, not the current candidate inventory.
See [public intake](lightpanda-public-intake.md) for exact hashes, resource
limits, positive/refusal coverage and teardown. No native, geometry, input,
pixel or WebMCP support follows.
