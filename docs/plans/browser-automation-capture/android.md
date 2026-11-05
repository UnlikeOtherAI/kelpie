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
test checks intersection center and decoded exported PNG marker pixels. The probe covers pre-play pinch only. Recording blocks ordinary renderer touches; iOS also locks orientation. Android currently has no matching orientation lock in MainActivity/BrowserScreen, so that parity gap is reported separately. No mid-play gesture or rotation is presented as a supported shared user flow. Common JS/CDP tests cover stale pinch-token rejection; native stale-viewport evidence remains unclaimed.
This probe is authored, not yet compiled or executed on either emulator profile.