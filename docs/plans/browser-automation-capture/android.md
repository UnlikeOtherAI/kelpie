# Android automation and capture

Source base: 9f752a56335a15e1662016dc6db934a79adba7b5.
Implementation owner: Android. Worktree: D:/Worktrees/kelpie/capture-android-20261104.
This is an implementation checklist, not a release or device-verification claim.

## Boundaries and dependencies

Strict v1 reuses the generated core-mcp validator, fixed semantic target reader,
canonical observation/extraction/readiness gateway and core-automation numerical
presentation model through JNI. Legacy scripts retain their own handler and lease.
No second schema, interpolation engine, identity store or native session allocator
is introduced.

The existing HTTP authorization decision supplies an immutable client/grant/listener
reference and a current authorization closure in private coroutine context. Actions,
frames, status, abort and chunks revalidate it. Callback/main-thread checks use the
current local pairing/account grant and listener. Body sessionId never authorizes
anything. Android has no native managed-session resolver: supplied sessionId fails
full preflight with SESSION_UNSUPPORTED. Inference/Nessie outbound calls without an
explicit recording authority cannot inherit recording permission from a connection.

Mobile press-key refuses in full preflight: Android has no existing verified
WebView key route, and iOS lacks equivalent supported defaults. A synthetic
KeyboardEvent is not substituted for browser keyboard behavior. Other input uses
the generated atomic synthetic-coordinate path and reports that guarantee. Android
WebView's page-realm object registry is a correctness fence, not hostile-page
isolation.

The native overlay renders one shared numerical timeline into both live View Canvas
and captured bitmap Canvas. There is no OS cursor control or persistent content
script. GIF uses an original bounded RGB332/LZW encoder with the requested marker
color reserved in its palette; GIF color quantization differs from lossless PNG.
Video uses Android MediaCodec H.264 and MediaMuxer, with encoded-sample admission
and reserved footer space. A terminal empty EOS sample supplies the final MP4
duration. The worker queue is bounded; rejected continuous frames are counted.

Only direct play replies contain bounded redacted named outputs. Status is
metadata-only: success describes the query, runSuccess describes terminal outcome,
and runError carries a fixed safe code. Opaque artifacts are current-owner/grant/
listener-bound; arbitrary files/URLs cannot be downloaded. Terminal private
workflow literals, output payloads and redactor values are cleared after the
direct response is built.

The shared native redactor C ABI has a thin JNI adapter; Android relink remains
pending. The four script descriptors still require common registry enablement.
Do not fork descriptors in Kotlin. Native route and supportedVersions checks remain
authoritative while the registry change is pending.

## Canonical 48-requirement checklist

Every evidence cell is pending unless an exact-revision result is appended below.
Shared implementation alone does not establish Android phone/tablet acceptance.

| ID | Android implementation or policy | Evidence |
| --- | --- | --- |
| OBS-01 | Canonical fixed value-free reader via BrowserGatewayBinding | Pending native canaries |
| OBS-02 | Canonical scope/priority reader | Pending scoped fixture |
| OBS-03 | Canonical bounded text/elements/metadata | Pending truncation fixture |
| EXT-01 | Canonical deterministic extraction sources/status | Pending missing/duplicate cases |
| EXT-02 | Canonical nested/repeated extraction | Pending ordered record cases |
| EXT-03 | Canonical bounded publisher metadata/JSON-LD | Pending private canary cases |
| EXT-04 | Canonical source/document provenance | Pending navigation comparison |
| RDY-01 | Canonical immediate page status | Pending actual DOM/diagnostics |
| RDY-02 | ScriptActions polls canonical tab.ready explicitly | Pending delayed/duplicate/hidden cases |
| OWN-01 | Managed allocation stays CLI/desktop; supplied native session refused | Pending no/unknown/foreign session cases |
| OWN-02 | Existing coroutine lease/retirement plus pinned WebView | Pending stale/late callback cases |
| WFL-01 | Core C ABI schema then native capability preflight | Pending public malformed admission |
| WFL-02 | Host bindings; unresolved refs refused; private redactor provenance | Pending native redactor ABI |
| WFL-03 | Ordered assert/readiness/extract/output actions | Pending actual ordered workflow |
| WFL-04 | Separate unversioned legacy handler; mixed v1 cannot fall back | Pending both public routes |
| WFL-05 | Mutation-in-flight plus fixed target uncertainty; never replay | Pending actual uncertain action |
| TGT-01 | Generated unique semantic target resolver | Pending unique/duplicate/disabled |
| TGT-02 | Generated visible center and hit testing | Pending obscuration and scroll |
| TGT-03 | CSS/bitmap scaling and native viewport checks | Pending phone/tablet DPR/zoom |
| TGT-04 | Generated object/document/token/geometry recheck after motion | Pending move/replace/navigation |
| TGT-05 | Explicit synthetic-coordinate input guarantee | Pending event.isTrusted oracle |
| PTR-01 | JNI core-automation S/C eased path | Pending displayed/decoded samples |
| PTR-02 | Same native overlay renderer and numerical ABI | Pending pixel/time comparison |
| VIS-01 | Native circle color/radius/alpha compositing | Pending PNG/GIF/MP4 pixels |
| VIS-02 | JNI wobble/fade state; clear at terminal cleanup | Pending early/middle/late frames |
| CAP-01 | ScriptCapture with GIF, MP4 and step PNG | Pending real decoded exports |
| CAP-02 | GIF LZW/loop/cumulative delays | JVM independent decoder passed; device pending |
| CAP-03 | Native H.264/Muxer timestamps and EOS duration | Pending Android decoder |
| CAP-04 | Every-step/explicit screenshot commands share native overlay | Pending manifest and pixels |
| CAP-05 | Captured native document/viewport/scale fences | Pending navigation/resize |
| CAP-06 | Shared schema bounds and shared media-byte budget | Pending native runtime bounds |
| CAP-07 | One queued command and bounded native codec input | Pending throttled encoder |
| CAP-08 | Stop/error finalizes each codec and preserves siblings | Pending partial + next run |
| ART-01 | Opaque registered files; bounded authenticated chunks | Pending cross-process/host reconstruction |
| ART-02 | Existing current authority plus immutable owner/grant/listener | Pending second/revoked owner |
| ART-03 | Strict integer/range/key limits and private file membership | JVM bounds passed; native pending |
| ART-04 | SHA-256/bytes/MIME/partial/timing/document manifest | Pending independent hashes |
| SEC-01 | No raw provider errors; shared redactor C ABI adapter | Pending encoded-secret vectors |
| SEC-02 | Fixed readers only; no arbitrary authored evaluation | Pending hostile page cases |
| DIF-01 | Same shared fixture and normalized mobile semantics | Pending iOS/Android comparison |
| LP-01 | Explicit unavailable on phone; optional desktop backend retained | Pending public capability refusal |
| LP-02 | No phone layout/input/capture promises for LP | Pending public refusal boundary |
| WEB-01 | Unavailable without real API and explicit host grant | Pending public unavailable response |
| WEB-02 | No page polyfill or page-declared authority expansion | Pending hostile declarations |
| DOC-01 | Android API/feature docs accompany implementation | Pending final implementation audit |
| UI-01 | Only requested overlay/recording changes; no new product panels | Pending supported native screenshots |
| REL-01 | Coordinator owns integrated PR/version/release | Pending coordinator |
| REL-02 | Coordinator publishes; Android owner verifies installed artifact | Pending signed published artifact |

## Verification environment and actual status

Maxis inventory is available: Android SDK platforms34/35/36, build tools34..36.1,
CMake3.22.1 and NDK25.1.8937393. AGP8.3's documented default NDK25.1 is installed,
so no host-only NDK pin or CI toolchain drift is needed. Java21 and Gradle8.6 are
used by the task. Task cache/output relocation uses KELPIE_ANDROID_BUILD_ROOT;
unset builds retain ordinary repository paths.

Existing Fermenta phone/tablet AVDs and the running emulator belong to other work
and have not been used, stopped or overwritten. A task-owned headless device may
be created only in the approved emulator slot, using the installed API35 image,
at most two cores and four GiB RAM. No image download is assumed authorized.
Phone and tablet evidence are separate. No physical Android hardware has been
inventoried or verified.

ANDROID-COMPILE-1 is running only formatting/JVM compilation/tests with one worker,
in-process Kotlin and2GiB Gradle heap. TEMP/TMP are D:/Temp/capture-android-20261104;
builds, project cache, Gradle home and logs are under
D:/BuildArtifacts/kelpie/capture-android-20261104. No emulator, native app launch,
Computer Use, VNC or custom OS input has run.

Initial Gradle invocation downloaded/configured8.6 but rejected a PowerShell-split
-D argument as a task name. It ran no formatter or tests. The corrected invocation
quotes native arguments and logs stdout/stderr directly; its results are pending.
ANDROID-COMPILE-1 final checkpoint: ktlintFormat, main Kotlin/Java compilation and
all173 JVM tests passed on Maxis with one worker/in-process Kotlin (1m15s,
compile-1-checkpoint.log). Added cases cover independent GIF decoding across LZW
width/reset boundaries, exact colors, cumulative duration/long holds and bounded
partial output; immutable owner/grant/listener scope; strict chunks/hash/ownership;
preflight session/keyboard/input refusals; redactor ABI envelope/fail-closed adapter;
and metadata-only finalizing/terminal status. One intermediate173-test run failed
because its test fixture precreated an exclusively owned directory; corrected
fixture passed. No actual JNI link, AVC decoder, HTTP/MCP script flow, emulator,
physical device, screenshot or installed release was exercised by this checkpoint.
ANDROID-NATIVE-1: merged dc0648e284c46582708b2ea31431de85a9f9946a, preserved
JNI UTF16/instrumentation drafts and froze source. pnpm bootstrap passed17.6s;
configureCMakeDebug[x86_64] passed44s; explicit CMake --parallel1 completed115/115
objects/links, including shipping KELPIE_LOCAL_LLM=ON. Installed default NDK25.1
was used. Output is the task-owned x86_64 libkelpie_jni.so; logs native-1-configure
and native-1-build remain under the task artifacts directory. SDK metadata version
warnings and archive version probes were nonfatal. This establishes native link,
not JNI execution, AVC decoding or public app flow acceptance.

Next source checkpoint uses root419bc2ca including the Android/Chromium registry.
Private pinned workflow readers use direct targeting with exact tab/WebView/current
authority checks; selected targeting without get-tabs would disable canonical
reads. Empty inputs:{} is accepted, but unresolved declarations/references refuse.
Any resolved sensitive target refuses capture. Semantic step PNGs are pre-input;
other step PNGs remain post-action. Movie marker phase zero stays stamped to the
old document until every requested movie acknowledges an encoded frame and one
requested interval passes. Then the configured animation clock starts, followed
immediately by exact-target recheck/input. Screenshot-only and uncaptured runs have
no added dwell. Step PNGs do not add movie samples or bypass the requested FPS.
Raw JNI NUL/malformed UTF16 refuse; escaped JSON NUL and standard UTF8 non-BMP
strings remain valid. Device tests cover repeated native allocation/free and these
boundaries; their execution is still pending.
ANDROID-COMPILE-2: root419bc2cad3a5b72d1e25a032bfb4e5a4aaaf209f plus Android
fixes. ktlintFormat, main Kotlin/Java, all175 JVM tests and
compileDebugAndroidTestKotlin passed (2m30s initial; final accounting/startup/test
warning cleanup rerun1m30s, compile-2-final.log). No new Android-owned compiler
warnings remain; existing unrelated warnings remain. Incremental shipping JNI
with registry and UTF16/ownership fixes passed8/8 in the explicit one-job build
(native-2-build.log). Standard UTF16 conversion rejects raw NUL/unpaired surrogates;
RAII releases JNI characters and C ABI allocations even when conversion throws.
Instrumentation cases are compiled, not executed: real UI pairing, direct HTTP/
MCP status, ready/extract, independent GIF/MP4 retrieval/decode, movies-only1FPS
navigation frame inspection, RGB/chroma/timing/min-budget video checks, UTF8/
escaped-NUL/redactor vectors and repeated native allocation/free. No emulator,
APK install, physical device, rendered UI screenshot or signed release was used.
ANDROID-EMULATOR-1 source preparation: real public flow coverage now also includes
zero-action preflight refusals, generic/direct MCP discovery and calls, native Stop
partial finalization plus next-run recovery, foreign-owner status/abort/artifact
denial and revocation, scoped value-free snapshots, nested/missing/ambiguous
extraction, publisher metadata, immediate readiness and unavailable diagnostics.
The existing Stop square has the accessible name Stop recording. MP4 keeps a
bounded four-input PTS-to-captured-document map; encoded acknowledgements never
borrow the current sample's document. Phone and tablet task-owned AVDs are approved
for sequential headless execution using installed API35 google_apis x86_64, at
most two cores/four GiB each. No profile has booted yet. The new cases still require
compilation/package and actual execution before any acceptance row can be marked.
ANDROID-EMULATOR-1 package checkpoint: ktlintFormat, all175 JVM tests,
assembleDebug and assembleDebugAndroidTest passed on Maxis (final incremental
39s, emulator-1-package-final.log). The initial2m50s run built the app but found a
Kotlin test-helper visibility error after common fixture extraction; making that
test helper public fixed it. APK is intentionally x86_64 only; the arm64 missing
library packaging note is not an ARM64 verification result. Shipping JNI/local
inference remains enabled. Verified copies are under packages/emulator-1:

- app-debug.apk: 86743669 bytes, SHA-256 887f5ce4d234fd34d97150bd155434a60a6b868c640599733f523d976263bddd
- app-debug-androidTest.apk: 2468146 bytes, SHA-256 aa12b6dd506d8173e8ea45875c84226f799d80581991cbe6dd5b6df500ef8cf5

No emulator/device test has run at this checkpoint. Source and docs are committed
before installation; later entries identify exact profile/serial and source.
Phone run1: committed ca498e21, Pixel7 API35 google_apis x86_64,
emulator-5584,1080x2400/density420; native Android window in a headless emulator
host (not a headless browser engine). APK hashes match the package checkpoint.
Initial detached launch ended with SSH; retaining the SSH process owner kept the
approved emulator alive. WHPX was operational. Both packages required adb -t
because the injected-ABI debug manifest is test-only; no other package/device was
overwritten. Native instrumentation ran11 tests:6 passed,5 failed. Raw output is
phone-instrumentation-1.log; adb exit0 does not mean tests passed.

Passed: JNI validation/numerics; non-BMP/escaped-NUL/raw-NUL conversion and100
redactor allocation/free rounds; movies-only1FPS semantic navigation with complete
authenticated chunk/hash reconstruction and every-frame GIF/MP4 old-document
marker checks; foreign-owner denial/revocation and new-run recovery; visible
native Stop with playable partial movies/new-run recovery; native H264 RGB,
dimensions, timestamps, duration and early finalization. Low-FPS artifacts had
five actual frames each,320x602, and8 reported drops; GIF duration13090ms and MP4
13085.606ms. Decoded GIF and MP4 marker frames were also visually inspected.
These counts describe this constrained emulator run, not a guaranteed throughput.

Failures: the test expected unlabelled div text in a semantic snapshot and a
heading ahead of a prioritized button at maxElements1; both assumptions conflict
with the shared reader. Schema discovery omitted required names. Shared redaction
scrubs/preserves unknown dynamic keys rather than dropping them, so pageSource's
synthetic value must be asserted masked. The1024-byte single-frame AVC test
produced no file but did not exhaust budget: nonblocking startup input admission
could discard its only frame. First input now waits a bounded interval or refuses;
non-budget empty finalization cannot report success. Captured-origin deadlines
now gate actions and post-draw frame admission, with terminal timestamps capped
independently of codec finalization time. New deadline and padded-width decoder
regressions are pending the next package/device replay.

Raw exports and decoded frames are preserved in phone-evidence-1. Only the task
phone emulator was shut down normally after this bounded run; AVD data was kept.
Tablet is still unbooted. The five failures remain unaccepted until replay passes.
Phone replay package: source fixes and fixture corrections passed ktlintFormat,
all176 JVM tests and both debug APK assemblies (2m35s,
emulator-1-replay-package.log); the final test-only contract/retention refinement
passed21s (emulator-1-replay-test-final.log). Href extraction is asserted as the
raw source attribute, matching the shared reader. Tests now retain AVC color media
and decoded frames, check padded-width RGB at center/corners, and compare both
shared curve branches. Native UI evidence waits for actual blue marker pixels.
MCP tests explicitly inspect the canonical ok/value envelope. Instrumentation has
not replayed yet. Verified copies under packages/emulator-2:

- app-debug.apk SHA-256 34fed03d6a3f6ac28a39239a4b9006d8c2e32bdc73ad0e1f3fc9f9b5c00b4126
- app-debug-androidTest.apk SHA-256 3e7afbd84d575552cfd8005e464b86a8739b03ad0631e112f3d0231725866529
Phone replay2: source80e7f7cd, same phone profile/serial and emulator-2 APKs.
Twelve instrumentation tests ran: ten passed, two failed
(phone-instrumentation-2.log,43.677s). Passing cases include the bounded first AVC
input, padded78x50 RGB decode, movie deadline interruption before a later click,
combined PNG/GIF/MP4 exports, private ready/extract and direct/generic MCP.
Raw exports are preserved in phone-evidence-2 and phone-codec-evidence-2.

One failure retained an absolute-href assertion despite the documented raw-href
contract; the multiline fixture assertion is now corrected. The Stop failure
reported VIEWPORT_CHANGED. Native screenshot inspection found the Compose test
clock had not committed the approved pairing dialog or recording chrome before
the test clicked Stop. That click drove pending layout and changed the viewport.
Tests now wait for pairing-dialog removal and native recording semantics before
status polling or Stop. The forensic screenshot is not accepted final UI evidence.
No viewport guard was weakened. Both corrections await replay. The phone emulator
was shut down normally, preserving data; tablet remains unbooted.

Pending source regressions additionally cover screenshots-only maxDuration during
a wait followed by an unexecuted click; same-document private target token
retirement; semantic fill/type; ambiguous/disabled/covered targets; mixed HTTP,
direct MCP and generic MCP artifact chunks; and generic MCP abort/recovery.
A single private resolver namespace replaces per-run page properties: each action
starts with a fresh no-token resolution and dispatches only its returned token,
under existing serialized renderer retirement.

Hosted Android CI41950362604 at28426edc failed testReleaseUnitTest:
OpenAIEndpointServiceTest.cancelReturnsInferenceCancelled,176 tests/one failure.
Debug JVM and shipping ARM64/x86_64 native graph tasks completed in that run;
the required overall check failed. The eager coroutine can enter the transport
before cancellation registration. A deterministic unconfined-transport regression
and queued/cancelled-scope lifecycle cases are staged. The fix and public local
endpoint cancel/retirement/recovery test still require execution. No CI rerun or
successful final-revision claim is implied.
Inference lifecycle checkpoint: the old-ordering deterministic case failed exactly
expected1/actual0 at transport entry (4m4s); inference-old-ordering.log and XML
are preserved independently of Gradle's reports. The lazy-register-before-start
fix passed ktlintFormat plus focused Debug19/19 and Release19/19 tests in4m10s
(inference-lifecycle-fixed.log). Cases include transport-entry cancellation,
queued-before-start cancellation, already-cancelled scope and worker cleanup.
The run used one worker, in-process Kotlin,2GiB heap/two logical processors,
without native/package/emulator jobs. Public device cancellation/recovery remains
pending; this result does not replace the failed hosted CI or final full checks.
Hosted build-only fixing run41956455688 passed on635d88ace7f2a7c3f722b4c572fa1e2d3f285945:
lint, ktlintCheck, Debug/Release unit tests and shipping ARM64/x86_64 native builds;
Gradle reported6m48s. Previous failed41950362604 evidence remains preserved.

## Opt-in hosted native verification

Android workflow_dispatch accepts native_test (boolean, defaultfalse). Its
dedicated Ubuntu24.04 job requires accessible KVM, builds the same revision's CLI,
shipping x86_64 debug app and AndroidTest APK, then cold-boots API35 google_apis
Pixel7 phone and Pixel Tablet sequentially. Source/APK/packaged-native/installed
APK hashes, image fingerprint, profile/display and version accompany the results.
Only one compiler or emulator runs at a time in this job. AVDs use two cores/3GiB;
Gradle uses one worker, two logical processors and a2GiB heap. No local Maxis AVD,
physical device, signing, publication or desktop input is involved.

The existing Compose pairing/Stop tests and real loopback HTTP, direct/generic
MCP, chunk/hash, native media decode, observer/target, JNI UTF8 and controlled
inference-cancel/recovery corpus run through AndroidX instrumentation. CLI is
built and hashed but authenticated host CLI replay is not claimed by this job.
An adb zero exit cannot establish success: the driver requires an explicit JUnit
OK count and rejects failure/crash markers. KVM absence/boot failure is a blocker.
Each profile shuts down before the next starts, including failure cleanup.

Seven-day artifacts contain curated fixture media/decoded frames/native screenshots,
instrumentation/boot/install logs, hash manifests, report.json and unit test reports.
They exclude AVD images, unrestricted logcat, pairing stores, endpoint secrets and
application databases. bash syntax, Node syntax and the report's false-pass/
missing-profile regression pass on Maxis. New Kotlin tests and hosted emulator
execution are compile/runtime-unverified at this source checkpoint; root dispatch
and actual per-profile results must close those gates.
Privacy/protocol follow-up (source checkpoint, runtime pending): inferred-sensitive
edit text is registered before refusal; captures are discarded by an independent
latch for privacy or redaction failure, while the first concrete error and
uncertainty survive cleanup/Stop. Redacted output is prepared exactly once before
terminal state/UI restoration. The four strict-v1 aliases match iOS; legacy is
unchanged. A native test checks raw/URI/form title output before implicit-password
refusal, no edit, masked earlier output, zero final/status artifacts and value-free
status. A JVM case injects a failed native redactor and verifies discard/error/
uncertainty survive subsequent failure and Stop.

Artifact tests now reconstruct the entire artifact independently through HTTP,
direct MCP and generic MCP, checking every echoed identity/MIME/length/hash,
offset, positive bounded progress and exact EOF under chunk/deadline bounds.
A deterministic noisy PNG exceeds262144 bytes to cross the canonical chunk
boundary. The hosted CLI bridge is excluded from the ordinary corpus, then runs
separately: native Compose approves the CLI's own persistent pairing request,
the actual CLI runs a screenshot workflow, queries pinned owner status and
downloads/hashes a large PNG. No bearer is copied or printed. Only non-secret
fixture URL/tab coordinates cross adb. CLI output/status/download evidence is
retained separately; a profile passes only when both native corpus and CLI bridge
pass. No physical-device/publication/signing claim follows from this emulator job.
Focused checks for this checkpoint: offline Gradle ktlintFormat dry-run graph
contained only source-format tasks (25s); exact formatter passed24s and final21s
with one worker, hard affinity mask1, ActiveProcessorCount1 and1GiB heap.
No compile/native/emulator tasks ran. bash syntax, Node CLI/report syntax and
report regression1/1 pass. The initial direct cached CLI formatter could not
start because CLI-only dependencies were absent; it changed no source and is not
a successful check. Kotlin compilation/JVM privacy test and actual hosted
phone/tablet/public CLI/privacy replay remain pending.
## G07 native pinch and pending resize probe

Source depends on integrated b3f2d93e/common34a39319: target x/y remain layout CSS,
and the same captured target frame supplies visualViewport offsets, size and scale.
Android's one live/export overlay canvas maps those coordinates by visual size and
offset, including pointer shape and tap radius. No separate numerical trajectory
or resolver implementation is introduced. A target is checked again after pointer
animation before the tap is shown/captured, then atomically rechecked at dispatch.

Normal shipping tabs now enable built-in WebView pinch while hiding zoom buttons.
Android's official WebSettings reference states builtInZoomControls enables pinch
and defaultsfalse; displayZoomControls false hides deprecated visible controls:
https://developer.android.com/reference/android/webkit/WebSettings#setBuiltInZoomControls(boolean)
The setting is in TabStore, never enabled only in a test.

The authored phone/tablet probe sends standard two-pointer Android MotionEvents
only to the exact visible app-owned WebView before playback. It records actual
scale/offset/size and requires real zoom/nonzero offset, not CSS zoom or a stage
transform. A partially visible button records the actual event and viewport; the
test checks intersection center and decoded exported PNG marker pixels. The probe covers pre-play pinch only. Recording blocks ordinary renderer touches; iOS also locks orientation. Android originally had no matching orientation lock; the focused orientation checkpoint below adds production parity with iOS. No mid-play gesture or rotation is presented as a supported shared user flow. Common JS/CDP tests cover stale pinch-token rejection; native stale-viewport evidence remains unclaimed.
This probe is authored, not yet compiled or executed on either emulator profile.
## Recording orientation parity

The browser's existing recording state now owns a thin Activity orientation effect:
lock the current orientation during presentation and restore the exact previous
requestedOrientation when normal finish/abort/failure changes recording state,
or when the effect disposes. No setting, product API or visible button was added.
Recording remains true until media/renderer/output finalization, so orientation
restoration follows retirement rather than an early Stop acknowledgement.

The authored phone/tablet case covers success, owner abort and a real missing-target
failure. It asserts the active lock, uses standard UiAutomation device rotation,
requires stable owned-renderer dimensions while active, then exact prior-policy
restoration and an actual resize from the same rotation request after termination.
This is an orientation-policy probe, not a bypass of the recording touch overlay
or a claimed mid-play viewport failure. Device rotation is restored only as normal
test cleanup after terminal assertions. Runtime results are not yet available.
Official instrumentation API:
https://developer.android.com/reference/android/app/UiAutomation#setRotation(int)
Orientation checkpoint source-format check: exact offline ktlintFormat passed22s with affinity1/one worker/1GiB, no compile/native/emulator. Kotlin compilation and actual policy/rotation assertions remain pending hosted verification.

## Hosted c71 execution: failed, evidence retained

Run41967310018 at c71aeabd513c4d19c5088cbae7202cd59fbb95f6 completed full build/lint
and hosted shipping app/test compilation. Retained Debug JVM XML totals180/180.
KVM was available; both API35 phone/tablet AVDs booted and ran22 corpus methods.
Phone17/22 passed; tablet19/22 passed. The separate native CLI bridge was1/1
on each, but both host CLI controllers failed before download on the large-PNG
expectation. Pair/run/status happened; full CLI download was not established.

Artifact13388674226 expires12November2026; original ZIP SHA-256:
70abfcf4b2420f0d119e7b96f688f8f7514b9dd328e6889794217df8b5cdc072.
The verified archive and unaltered extraction are preserved on Maxis under
D:/BuildArtifacts/kelpie/capture-android-20261104/hosted-41967310018.

Both profiles passed real public controlled inference cancellation/retirement/
recovery, native orientation lock/restoration on success/abort/failure, scoped
observations/extraction/readiness, JNI Unicode/NUL/provenance checks, low-FPS
movies, owner/revocation controls, generic MCP abort/recovery, deadlines, target
ambiguity/obscuration/label edits and native video decode/budget cases. Phone
combined capture and native Stop methods failed; their old assertion helper
discarded the error body, so their exact failure cause remains unclaimed.

Both failed noisy PNG size, fractional event getter expectation and the UTF-8
privacy fixture title. The tiny images were not downloaded before the old size
assertion. The new harness waits for the new canvas document plus draw-complete
title and retains original native/captured negatives before size checks. Fixture
entry now requires its unique DOM sentinel and stable native geometry, not an old
document's complete state. Explicit UTF-8 fixes the title precondition; c71 URI/
form values were masked and capture discarded, but that failed method is not a
full privacy pass. Chromium clientX/clientY getters floor fractional values:
https://raw.githubusercontent.com/chromium/chromium/main/third_party/blink/renderer/core/events/mouse_event.h
The new test checks exact floor and less than1CSSpx error; core coordinates and
native PNG center/page-underlay checks remain fractional and unchanged.

Original native phone/tablet screenshots were independently viewed by worker and
root with hashes verified: actual blue circle/pointer centered on Submit, visible
Stop. Read-only image ROI analysis found phone component8689px at418.73/581.33
versus button421/583; tablet5616px at319.5/387.5 versus320/388. This accepts only
the native spatial/visible UI case, not failed phone Stop invocation. All18 retained
decoded low-FPS frames were also viewed. Phone5frames/format at320x652 showed
old-document marker,2drops, GIF6860ms/MP4 6857.174ms. Tablet4frames/format at320x186
showed old-document marker then final Destination,1drop, GIF5220ms/MP4 5218.475ms.
Phone destination-frame presence is not claimed.

The native screenshot guard now scopes to owned WebView intersected with actual
Submit accessibility bounds and checks component area, shape, centroid and center
coverage. An authored counterexample test rejects unrelated chrome, focus rings
and thin text fringes. The runner now requires github-hosted Linux, rejects
preexisting proposed serial/ports, verifies spawned PID generation/SDK binary/AVD/
port and console AVD identity before mutation or termination, and preserves failed
JUnit denominators. Node guard/report4/4 and shell/Node syntax pass; new native
checks remain compile/runtime pending. No local emulator/heavy build was launched.

Critical separate gate: common review reproduced focus-time sensitivity changes
(text to password/autocomplete=current-password) leaking earlier outputs/captures.
Android needs the common private policy and pre-guard result-consumer adapter;
the initial-password case does not cover or close that gate. Next hosted run must
include that common fix and native focus-time cases.
## Late classification and publication follow-up (source only)

The Android fixed-target callback now consumes token-latched sensitivity before
current-document checks and before releasing its existing renderer-retirement
ticket. Capture uses the shared private refuseSensitive policy. Missing or
uncertain classification after attempted editing registers the current editing
literal even without capture; capture additionally latches discard independently
of the first concrete failure. Final outputs still wait for renderer retirement.

Running/finalizing status returns no artifact manifests. Owned active-run
downloads return ARTIFACT_NOT_READY after parameter validation; unknown/foreign
runs return ARTIFACT_NOT_FOUND. Prior safe terminal downloads remain available.
The publication transition and read share the run monitor.

Authored regressions add focus-time autocomplete/password changes with earlier
raw/URI/form output, plus public HTTP/direct/generic MCP early-download refusal
and a prior terminal download during a new run. JVM ownership cases exercise a
known current artifact ID in both active phases and privacy discard afterward.
These additions have not been compiled or run on a device in this checkpoint.
The c71 hosted failure denominators above remain unchanged.
The classification fallback is scoped to an actually started fixed evaluation
without explicit Boolean metadata. A decoded sensitive:false followed by a
document/abort guard failure preserves ordinary partial capture and does not
register the editing literal. A pre-evaluation refusal also leaves provenance
unchanged. New JVM vectors and a real-WebView callback guard regression cover
these boundaries; they are authored but not yet compiled/run.
Lost classification protection also applies to initial click/tap resolution and
non-dispatch target rechecks, not just edit/dispatch calls. The fallback latches
capture discard for these stages while literal registration remains editing-only.
The callback regression includes a real missing-metadata click-stage result.
The shared follow-up adds sensitivityKnown: only sensitive:false with
sensitivityKnown:true certifies nonsensitive provenance. Missing/legacy fields or
missing-token/new-realm failures remain unknown after evaluation starts; a true
sensitivity flag always protects. The thin tracker consumes both fixed fields.
This adapter must ship with the matching regenerated common helper.
Successful target edits are also checked for late sensitive metadata: capture
refuses after the mutation with mayHaveCompleted:true, discards every artifact,
scrubs earlier outputs, and executes no later action. Without capture the edit
may finish and earlier outputs are still scrubbed. Existing concrete helper
failures retain priority. Four authored oninput autocomplete/password ×
capture/no-capture cases cover this boundary; native execution remains pending.
## G08 hosted adapter (source only)

The hosted authenticated CLI bridge now runs the shared white fixture separately
for C and S on each profile, retaining ordered fixture facts, full GIF/MP4
downloads, hashes, frame timestamps and the shared streaming verifier result.
The fixture binds host loopback and the emulator reaches it through 10.0.2.2.
The native bridge remains active through both runs. This is authored integration,
not a device, decoded-pixel or native-overlay acceptance result. Failure reports
and partial evidence remain retained; the shared verifier determines pass/fail.

## Hosted b927 evidence intake

Run41977011583 froze b927cb999509e25e3c85f3012620713b736dc73a.
The retained archive SHA-256 is
ac21e8b780352a36858cb0fd4d3d42b493741fdcb70ddb6318f23415130169fc.
Both phone and tablet ran27 cases with6 failures; both separate CLI runs failed
the PNG size assertion. Old c71 denominators and this failure remain preserved.
The b927 artifact MCP error and focus-time privacy cases predate integrated
follow-up fixes and need final-source replay, not a retrospective pass.

The noisy page's retained DOM state confirms drawn random canvas data; the phone
native screenshot is 5165243 bytes while the exported640x1304 PNG is a blank
6146-byte white image. The pinch export independently failed its red page
underlay check. ScriptCapture draws the WebView into a software bitmap; the
evidence points to missing hardware-composited WebView content. This remains
a production capture blocker pending a fenced compositor capture and replay.

Both native marker tests failed while their retained five-action play reply
succeeded. The rejected phone screenshot shows the finished browser without
recording chrome. The test waits for Compose idle both before and inside its live animation
sampling loop. Those waits can defer screenshots until the marker disappears.
The source removes both waits for this probe; bounded native
screenshots and main-thread geometry sampling remain. It requires replay.
The separate native Stop test completed with partial GIF/MP4 and SCRIPT_ABORTED
in this run; this is b927-only evidence, not a final-source acceptance claim.

## Compositor replacement (source only)

Strict capture now requests the exact certified visible WebView rectangle from
the parent Window after a WebView visual-state callback and committed-frame
callback. It rechecks current grant, document, scene generation, dimensions,
scale, window focus and bounds before and after the copy. Timeout or cancellation
quarantines one private bitmap until the late PixelCopy callback recycles it;
no later copy is admitted while it remains outstanding. The live
marker already belongs to the sampled frame and is never painted a second time.
The existing Stop control uses a separate non-focusable Popup, and recording
hides other browser sheets. Rounded staged viewports remove clipping while recording so the complete page
rectangle can be certified; API28 fails closed pending a verified frame fence. New native tests
cover uncertified-scene refusal and Stop exclusion, alongside the existing
noise PNG and pinched underlay cases. Compilation and device replay are pending.

Focused Maxis source check: after one formatting-only preliminary failure,
ktlintFormat, ktlintCheck, compileDebugKotlin, compileDebugAndroidTestKotlin
and ScriptPixelCopyGateTest3/3 passed in4m40s. It used a fresh writable Gradle
home, separately copied read-only modules-2 seed, one CPU and2GiB heap. Existing
unrelated warnings remain. No emulator, native screenshot, media replay, API28,
or signed release was exercised by this check.

## Scene and geometry follow-up (source only)

The scene predicate explicitly tracks inspector, tab overview, address editing
and menu, sheets, welcome, pairing and queued panel requests. Native action modes
and direct inspector/panel transitions invalidate a monotonic generation before
any frame can publish. Browser chrome is unmounted during recording; its transient
state remains uncertified until disposal. PixelCopy bounds use the full view
matrix and admit only fully visible positive uniform scale with pixel-aligned
edges. Rotation, skew, nonuniform scale and fractional boundaries fail closed.
AndroidX cases exercise tab-overview/address entry and restoration, action-mode
and inspector/panel generation, a pixel-aligned scaled owned view with
nonuniform rejection, and tablet stage screenshot restoration across success,
abort and failure. These are authored cases, not native pass claims.
Hosted run42006190219 at b2bcb247 failed lintDebug before the native job: lint
could not propagate the API29 guard into the frame callback. Follow-up cffe3a96
isolates the guarded callback in an annotated Q-only method. Historical run
remains failed; the integrated rerun must establish lint and device behavior.
Maxis follow-up check: online ktlintFormat/Check, lintDebug, main and
AndroidTest Kotlin compilation, and targeted gate/scene JVM tests4/4 passed
in2m25s with one CPU and2GiB heap. Previous offline lint dependency and
AndroidTest import failures remain recorded in scene-geometry-check.log and
scene-geometry-online.log. Device cases remain authored, not executed.

Hosted42007603401 at65fe4866ac7c4f0c4f43b240cfecb41471c0239f: build/lint
passed; phone30/33 and tablet29/33 failed overall. Both focus-time privacy
cases published three captures and returned raw, URI and form synthetic literals
unredacted; this is a release-blocking leak. Both combined-marker tests failed
initial CAPTURE_VIEW_UNAVAILABLE; tablet low-FPS navigation failed with
SCRIPT_DOCUMENT_CHANGED. Phone low-FPS navigation passed. Both profiles
reconstructed large nonblank PNGs and completed CLI baseline downloads;
native Stop returned SCRIPT_ABORTED with partial GIF/MP4 on both. Phone G08
exceeded its old18s capture deadline with316 dropped frames; tablet's G08
reached download but the runner lacked ffprobe. Artifact13406619597 SHA-256
0fec30a6a11a7b1658926a94cd81a46cd702b42ef0ae7d126a81d05662bf2cb1 remains
retained with the original failures.

Focus fixture follow-up records only focus/active-element booleans, event
count, bounded type/autocomplete categories and a fixed JNI expression hash
before existing assertions. It does not record input values. These authored
diagnostics have not run on a device.


The user approved Android 10 (API 29) as the minimum supported OS on 5 November
2026. Earlier API 28 refusal records remain historical; final-source phone and
tablet acceptance, including privacy and scene evidence, remains open.

Hosted run `42015326445` at `ee22cb800fa1ccd2f2ff587d99fb26b41a24fa47`
recorded three failures in each 39-case profile: two focus-sensitive privacy
cases and the native Submit-marker probe. The focus facts show
`document.hasFocus() == false` before and after the edit, zero focus events,
and `activeElement` set to the input; the generated expression included the
refusal policy. The edit proceeded without the focus handler and exposed the
synthetic literal in earlier output. Low-FPS navigation passed on both.
The CLI baseline retrieved decoded multichunk PNGs, but G08 C hit the 26-second
limit on both (phone 20 frames/471 dropped; tablet 38/456); G08 S did not run.
These outcomes do not establish native privacy or dense motion acceptance.
Local Maxis API 35 phone replay at `a05dd952c9901ebcb70f356f0227349059303445`
passed all seven privacy cases, including both focus handlers and refusal before
input; the installed APK SHA-256 was
`6bd9430e7f97dec1bb0b96a9627e2882c611df032d09c88d1bf630d456aa16b4`.
At diagnostic `e796ef343500123f3e5364cb7293c69505a20476`, G08 C returned
`CAPTURE_FAILED` after all six actions, with 65 frames and 360 dropped. The
encoder consumed 21.57 s over 65 samples; visual, commit and PixelCopy stages
averaged approximately 85, 53 and 83 ms. The marker was published and drawn
with matching document/viewport, but every native probe had a null accessibility
target, so the pixel detector was not invoked. Neither result closes the motion
or native visual acceptance gates. A sampler-finalization cancellation is a
source-identified candidate for the failure and requires device replay.

## Local phone and tablet evidence

Android 10 (API 29) is the approved minimum; API 28 notes above describe
historical candidates, not current support.

On the task-owned Maxis API 35 phone and tablet, the checked debug app
SHA-256
`9b28f1ccc0d50a162a851a6e401ac4949e8a08e7be06a819067e532068c54a51`
and test APK SHA-256
`547f463081bc43d5d0fbd4b932f6e8c4aef073228e3312a0bcc7cf452c395585`
passed the public HTTP/MCP native marker flow and the actual Stop control's
partial-movie and next-run recovery test. The independent native screenshot
SHA-256 values are
`45e769b9dce669ab749a2fcbd3ed8a9e5f44301d2bf85bbd7ecf6300376a6c22`
(phone) and
`229eb877b5363a780accfe1dc7d7fe674eca124d3d07103132a73dcf8a524492`
(tablet). The earlier marker attempts and startup ANR remain failed evidence;
a later readiness-admitted phone Stop replay passed.

A same-phone SwiftShader comparison of the above app and conversion candidate
`11384080b6545dfbb08a93e35b44cfc10efa5bbd` (app SHA-256
`ed2a086f5ccfe4c076cfac550f1f8c776ed5c9f658705f1f34b53fcb777be824`)
passed two native codec tests for each. The C and S conversion phases averaged
72.2 and 70.6 ms per frame before, and 55.8 and 51.9 ms after. Both captures
still yielded about 100 frames over 28 seconds; every GIF/MP4 dense-motion
oracle returned insufficient evidence. The previously observed sparse output
is retained and dense acceptance remains open.

The omitted-duration 350 ms motion, 500 ms control, capture-disabled isolation,
full public corpus and inference cancellation remain open on both device
classes. The explicit 400 ms marker and 2400 ms dense runs are not substitutes.
These local runs do not establish final signed-release acceptance.

On the API 35 phone, an omitted-duration G08 run using app SHA-256
`3a9664189db0351ee34fa01e4747392169c714e230e770aaf3aab097b3400984`
and test APK SHA-256
`c6ce5d92d25c8cab70f14a4ee97152cfc4caf8fa715fbffd6a0d516e698a7e5d`
completed with native screenrecord plus GIF/MP4 downloads. The screenrecord
contained only three interior final-move samples, including a 157 ms gap;
the shared fitter rejected it as insufficient. The explicit 500 ms control
had seven interior native samples and was rejected as a 350 ms fit; its
exports were also insufficient. The capture-disabled control timed out in
navigation before playback and remains unverified. Its emulator became
unresponsive to normal shutdown and exited at the original 30-minute Job
watchdog (code 124); the captured runs were pulled before that failure.
These are scoped test results, not a short-motion acceptance pass.
The API 35 phone no-capture navigation and final tap completed with app SHA-256
64b9f02f525ff096f891daeb5c692940472a376f2a9c92443b7b95012c594de4 and test
SHA-256 ba7fc658b7b63bf4954a09993198a594d430c4871a8dc9e4ed7c1cce8bfa9b43.
The native blue marker was not found. The first poll reported a visible target
116 ms after polling began; the final marker first-draw log measured an overlay
height of 1794 px, while the post-response WebView measured 1631 px. This
supports investigating layout change but does not identify the exact retirement
branch. Phone PNG/next-run and all tablet retirement cases remain open.

With the active/immersive layout split, API 35 phone no-capture and
screenshots-only public final-marker tests passed. The screenshots-only marker
was centered at (418.69, 508.21) in target [262,430,577,588]; its retained PNG
SHA-256 is 7e872eafe75b6e3851be8d1e29d6414843f276772653399ebb8f557e2d88abb1.
The native Stop test passed with WebView frame (0,63,1080,1631) before, during
and after. The no-capture screenshot was overwritten by the next case; its
instrumentation assertion remains, but its image is not retained. The separate
input test failed before execution because its generic test Activity was not
declared. Phone explicit-PNG and movie controls remain unrun.

The tablet no-capture public workflow succeeded but its final native marker was
not detected. First poll was 239 ms after polling began; the final first-draw
log and post-response WebView both reported 2560 by 1266 pixels. The final
rejected image SHA-256 is 17506523d5156337cce349e9c36fc3ac859064c8673f2ff7b0ee2cedb6e99400.
This does not establish the reason for retirement. Tablet PNG, Stop and movie
cases remain open. Both runs used app SHA-256
4c412fc82eadfe8daf8246235f8456e6b4735b76c689a5bc375dd93d8985f84e and test
SHA-256 7169e038d25de9f3c73fcbc67c3c7ac3e97642e839c181ba3b75a32329b62cec.

A separate instrumented API 35 tablet run passed the same no-capture native
marker assertion. The diagnostic app SHA-256 was
f6d497acf57a35aceba298400f5987176f4206296654925aa5176462067c5c12 and test
SHA-256 187f108a1675d865872ec4777c9f5eafbfb60da8860f39c81a856dca55edc41a.
The retained screenshot SHA-256 is
01fa285a1e135cb7d00b885eb65dc003393c37ec721b9854f7f6e163dae7e553.
The marker was centered at (319.5,485.5) in target [200,426,440,546], with
center coverage 1. The debug trace recorded retention accepted 332 ms after
marker publication; the first screenshot was acquired 1.62–1.97 s after
publication and the marker expired at its original five-second deadline.
This diagnostic adds instrumentation and does not explain the earlier 2d8
tablet failure. Tablet PNG, Stop and movie checks remain open.

The hosted API 35 KVM phone and tablet acceptance run
[42129812351](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42129812351)
used source 2c1ac38d11536fa90c6f38acdf87211bba1e428a and the same installed
app APK SHA-256
8ab4a84eeb1927b6d9e27cdf9811c0a11a9847b948c8c334fa94632b334244cf
on both profiles. The built test APK SHA-256 is
5ad8963546e2f14e17c57f7bd39c23f35e3c582f4e97737abec647735e1b1428;
the workflow did not retain an installed test APK hash. Its CLI index SHA-256
is 1b808c37502b1b218dc2b9d0ebe7304b0d8f84eff0054b553f30c3072ad8e4b5,
and packaged native library SHA-256 is
25ca3deab222e9e0381961fdebbb1712236f469a14cb48ffd04580cd171b1d68.
Build and lint passed. The phone instrumentation reported 58 tests and five
failures; the tablet reported 58 tests and four failures. These are emulator
results, not physical-device or signed-release acceptance.

Both native navigation Stop receipts report SCRIPT_ABORTED and
mayHaveCompleted: true; their test bodies reached recovery, but both cases
failed when the delayed-response MockWebServer timed out during shutdown. The
receipt SHA-256 values are
616aaa80525c101aa4ab373ec551a76c0d73be159c3195fcd0ef4f0c3ee4d510
(phone) and
acca301fc2a195359110165dbcaff9116c15862cb7252cb6961bcec6f50e430e
(tablet). The real chrome-input case opened More before playback, then failed
while dismissing that popup; active input blocking was not exercised. The
PNG next-run marker case detected the original marker but could not exclude
natural expiry before its next screenshot. Neither outcome proves a product
input-blocking or retirement failure.

Both navigation-scale cases returned VIEWPORT_CHANGED when the physical
WebView size remained fixed and the destination document changed native page
scale. The run-wide scale guard is inconsistent with this observed navigation;
the exact guard site was not instrumented. The phone address-editing screenshot
also returned VIEWPORT_CHANGED, with cause unresolved.

Authenticated CLI pairing, run, status and artifact download succeeded on both
profiles. Both CLI bridge cases nevertheless received complete:1 because
their later host capture checks failed. Phone C/S GIF and MP4 checks reported
insufficient dense samples or a missing pre-dispatch baseline; tablet capture
ended with CAPTURE_DURATION_LIMIT before verification. Dense capture, short
motion and the full public corpus therefore remain open.

Artifact 13465656715 has GitHub-reported SHA-256
33a3028019c5e82065f19c6380a63d669d40d26b24b52cc17f96a0de3fc00bbd.
All 180 phone and 187 tablet exports listed in its report were present and
matched their recorded hashes. Report SHA-256 is
9eb111096b97d2c2b6f7454d03b36a5f839897916bc0288394a4b6d6737a5003;
phone and tablet instrumentation logs are respectively
f2ab740b7432d205dd53c194b66a6e3775d03d08b1af2461d0b67d1d85d3f16d and
7abbae1a41bacb0b93e6c8da5b38c578ca60c24d3a20deaf7a6cc4bc6265a5ec.
The hosted job ended and retained its logs; independent post-job process
cleanup was not observed.

Independent inspection of the hosted native screenshots found the blue marker
and virtual pointer centered on Submit with native Stop visible on both
profiles. Their SHA-256 values are
e6f6dfc4dabaf375c88d5e5fef91801adb08e7ecb2515932cc07a8fb7ba0741d
(phone) and cb30cc2a46bedd3d8dd836d7142f2fb727c3a016b066b224f0d22ae54ebd5b07
(tablet). Separate native Stop images showed Stop with no marker, with hashes
c3f07367acc85baebcfdf42ec9e11f82b3dd3ce4f44684fff011fcbb2fe22ad2
(phone) and 21bdd5b17169c8b295a334468926afc9c3cbb3e72d1abd9c9e182d71fa76cd58
(tablet). The image alone does not resolve whether an earlier marker retired
naturally or because of a subsequent run.

The opt-in hosted run
[42141182122](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42141182122)
used source 225d68d7ec97196a03e57d54268c1d26b53cdb77 on API 35 phone and
tablet emulators. Build and lint passed. The built and installed app APK
SHA-256 was f0256ebac29a8c09cedae26e55f1ee6daa63c7a7ce4ebba9580293670770d82d;
the built and installed test APK SHA-256 was
b24b36850726f30b018ffc9d886f7e1906e398e5626b0a176ccea75cc8e8bf30.
Both profile cleanup receipts report the owned emulator PID and ports retired.

The native Stop during an observed pending navigation passed separately on
phone and tablet, including SCRIPT_ABORTED, mayHaveCompleted, one request and
recovery. Their instrumentation log SHA-256 values are
05f6aface463094653dd0029c4fadf3c28bde0c5d953cf36b5b2b0a207b6b918 and
c78c655c03db0dc068da3e3a9e0a4dce0165ba0154f1378d28fa1f2b2456f8f5.

The owned chrome/input test failed on both profiles. It confirmed a baseline
Enter reached the page once, opened and dismissed the owned More popup during
admission, and reached native Stop. After a second owned decor-dispatched Enter
during playback, the page counter was two instead of one. Phone and tablet
instrumentation log SHA-256 values are
ff118777346bc9355f04e678720a87b25ccd87d7789a4809c30e11da9bc748d2 and
cda902a697039d8d654e1888adba8ede26620bbdfbc005c6460eca4bd9ed7500.
Hardware keyboard input blocking is therefore not established. The targeted
run did not exercise the full corpus or the document-scale fix. Artifact
13469511332 has GitHub-reported SHA-256
551543d10634aef729919e4629c58cfdae74cf173bb4809954e2e01cf191baba.

The opt-in hosted run [42145950644](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42145950644)
used source b39d11911f6f21fde34de128c5a0df4d9cf7c8e8 on API 35 phone and
tablet emulators. Full Android build and lint and the shipping JNI app/test APK
build passed. The built and installed app SHA-256 was
98b2bcb42663dbb032975529cfd70f5c48f1d89eac3237ed7a183e9fc9722b17; the
built and installed test APK SHA-256 was
17f425f6c1a0775aa8aaab7cc384ff850cd73122397a99aaf2dc959c0d58042b.

On both profiles, the public delayed-navigation Stop case passed with
SCRIPT_ABORTED, mayHaveCompleted: true and recovery. The owned WebView
Enter down/up control passed before, during and after playback: each count
remained 1 during playback and reached 2 after Stop, with the same URL and
owned popup control. The separate renderer system-key test failed before
dispatch on child.requestFocus(); it establishes no system-key delegation
result. Both cleanup receipts report CLEANUP_CONFIRMED. Artifact 13472040144
retains the individual logs and receipts. The overall native job failed, and
this scoped result does not establish API 29 or full-corpus acceptance.

The opt-in hosted run [42152217154](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42152217154)
passed build/lint and all three selected cases separately on API 35 phone and
tablet at source ffeaf3ec2c33af0055f2bd0e8ad52b625e265307. Each profile
passed public navigation Stop with SCRIPT_ABORTED and mayHaveCompleted true,
followed by recovery; the owned WebView Enter down/up counts remained 1 during
playback and reached 2 after Stop, with the same URL. The focused native child
test passed its before/during/after Enter and system-key delegation assertions;
this is not a physical HID test. Both cleanup receipts say CLEANUP_CONFIRMED.

The app built and installed on each profile had SHA-256
eabac321de5dae3283afd15415cadd6ab178cb627155265f1d58b61578ba6dfb; the test
APK had SHA-256 ba38cee6864418ee24afa2ccd209a99525de567bced3f834fb9349927c7b8648.
Artifact 13473018753 retains the individual receipts. These targeted results
do not establish API 29, full-corpus or cross-platform acceptance.

The separate opt-in hosted run [42149256629](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42149256629)
also passed build/lint and the same three selected cases on API 35 phone and
tablet at source abde81c2474d667fd423f69aed7fbfc980073430, after a delayed
media-tool installation. Each profile passed navigation Stop with SCRIPT_ABORTED,
mayHaveCompleted true and recovery; owned WebView Enter down/up counts remained
1 during playback and reached 2 after Stop with the same URL. The focused
native child before/during/after and system-key delegation assertions passed.
This is not a physical HID test. Both cleanup receipts say CLEANUP_CONFIRMED.

The app built and installed on each profile had SHA-256
147cd03dd5f9c84ef7b3dde95cd474a836315d186fe5c5a29d1688c4334a81f0; the test
APK had SHA-256 eedce88d0c66f821e388325db0c136fcc41148619ad5a0e6d53be0b7530e8116.
Artifact 13473544679 retains the separate case receipts. This targeted run does
not establish API 29, full-corpus or cross-platform acceptance.
