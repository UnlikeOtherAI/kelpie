# iPhone and iPad workflow capture

The iOS app uses the frontmost WKWebView in the selected tab. The caller sends a version 1 workflow to the paired listener. During playback the existing recording screen shows Stop and the web viewport. A transparent UIKit view draws the optional pointer and tap indicator. WebKit snapshots supply the page pixels for step PNGs, animated GIF and H.264 MP4. The app stores files in protected private temporary directories and returns run-owned artifact IDs.

## Implementation and verification

The common [acceptance matrix](acceptance.md) defines the IDs. Each row below needs an iPhone result and an iPad result wherever the native scope applies. The generic iOS simulator app and both XCTest bundles compiled. Installed HTTP/MCP/CLI use, manual visual inspection and runtime artifact hashes are pending. Generated media and test bundles belong under ignored build artifacts.

| IDs | iOS implementation | Evidence to record |
|---|---|---|
| OBS-01–03, EXT-01–04, RDY-01–02 | The persistent browser gateway uses generated shared observation functions in a private WebKit world. `IOSWorkflowActions.read` calls the same gateway and returns its value. | Run the shared catalogue fixture through the paired app. Compare redacted priority, nested records, metadata sources, unavailable diagnostics and incomplete selection on both devices. |
| OWN-01–02 | The existing pairing grant, listener incarnation and exact WKWebView identify native ownership. `IOSScriptGrant`, `IOSWorkflowTab` and the short admission lease preserve the existing document and browser reference boundaries. The managed worker allocator belongs to the Playwright backend. | Pair two clients, rotate a named grant, revoke during playback, reload the same URL and exercise the existing pinned Nessie journey. An explicit native session ID must fail with `SESSION_UNSUPPORTED` before any action. |
| WFL-01–05 | `IOSBoundWorkflow` validates the full script with the generated C ABI. `IOSWorkflowRunner` checks the grant for each action and sampled frame. `IOSRendererDeadline` fences a late callback. `IOSWorkflowActions` runs waits, assertions and extraction in order. The unversioned legacy handler retains its own admission. | `IOSWorkflowAdmissionTests` covers strict fields, secret references, minimal byte budgets and unsupported actions. Check invalid late steps produce zero earlier mutations, user Stop and caller disconnect recovery, plus a late mutation with uncertain completion. |
| TGT-01–05 | `IOSWorkflowTab.target` evaluates the shared generated resolver in the private world. `IOSWorkflowActions.interact` pins token, document and visual viewport across pointer presentation and capture, then uses atomic synthetic coordinate dispatch or focused text edit. | Verify unique/ambiguous/covered/replaced buttons, clipped center, zoom, scroll, focus movement and native document replacement. Record actual fixture coordinates, action count and honest synthetic input guarantee. |
| PTR-01–02, VIS-01–02 | `IOSWorkflowPresentation` and `ScriptOverlayDrawing` use shared S/C easing and marker color, radius, wobble and fade. A noninteractive sibling overlays the WKWebView. The compositor latches that state's timestamp until the renderer returns. | Capture real app screenshots with native Stop and marker on iPhone and iPad. Compare decoded frames and the displayed marker within the captured interval. Inspect separate C and S motions and fading tap states. |
| CAP-01–08 | `IOSFrameSampler` limits WebKit to one snapshot in flight and counts skipped cadence slots. `IOSWorkflowMedia` writes step PNGs and stages GIF frames, then uses the shared Apple encoders. Native or same-document viewport resizing ends the capture with a partial result. A new document may change its CSS layout inside the same native canvas. | Decode the downloaded formats, measure PTS, GIF loop/delays, dimensions, step indexes, colors and fade. Check normal navigation, resize, Stop, time/byte limits, memory and recovery. Validate screenshots captured before input still correspond to the resolved target. |
| ART-01–04, SEC-01–02 | The shared artifact store serves bounded chunks after a fresh grant check. Redaction, sensitive-target refusal, private files and opaque IDs protect page data. The CLI owns transfer integrity and no-overwrite policy. | Through real HTTP/MCP and CLI, compare actual chunks to size/hash. Deny foreign grants, old listeners, bad offsets and secret-bearing captures. Verify no raw paths or bearer material reaches output. |
| DIF-01 | Typed outputs and manifests use the common schema. | Compare the iPhone and iPad results to the same native corpus revision on other platforms. |
| LP-01–02, WEB-01–02 | Lightpanda runs as a restricted desktop worker. The native WKWebView has no operator WebMCP grant provider. Native requests for unavailable operations must refuse without executing page-provided code. | Check the actual iOS capability catalogue and unsupported result. The separate backend owner verifies real Lightpanda and granted WebMCP calls. |
| DOC-01, UI-01, REL-01–02 | This platform note links the shared workflow guide. Release version lives in `apps/ios/Project.swift`. | Attach matching base/final evidence for visibly changed iPhone/iPad recording states. Record the integrated source and actual signed, installed release separately from simulator evidence. |

The full hosted run at `0d3d4e892b3993baa5fbac97e27a8aec9396767b` passed 26/39 iPhone and 27/39 iPad tests on iOS 26.5. Both installed binaries matched before and after testing, and both simulators shut down cleanly. Paired CLI playback timed out on both before G08; no G08 media was produced. Real navigation passed the warmed delayed-HTTP test on iPhone but iPad's warmup remained loading and failed. Both cold public navigation requests succeeded with one destination request, but their subsequent readiness assertion failed. Other failures include captured sensitive focus reporting `CAPTURE_VIEWPORT_CHANGED`, MCP workflow failures, native pinch geometry and a motion pixel threshold. The iPad GIF measured a red-minus-green difference of 168, exactly the ideal value for the fixture's #F000AA at the shared 0.7 opacity; its old >190 assertion assumed the former opaque marker. The replacement checks a bounded palette/fade tolerance around the 0.7 baseline and retains the separate motion, wobble and fade assertions. The retained XCTest bundles and attachments carry the separate outcomes; none is treated as a pass on another device. The initial iPhone fixture screenshot shows Submit visibly in the viewport. Fixed-enum viewport diagnostics and sanitized terminal error/action metadata are added for the hosted `diagnostics` scope, which selects the affected paired CLI, readiness, privacy and media journeys alongside navigation tests; the cause is not yet established. [Hosted run 41993388105](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41993388105)

The focused hosted replay at `4592d4a405c97b2e033cdf11d682773777650771` passed 7/16 tests on each device; both simulators shut down cleanly. The retained result identified observation failures in readiness and extraction, and viewport changes around snapshot capture. Source review found that a workflow-owned observation uses the selected-tab gateway, whose real `get-tabs` inspection was rejected by the same recording gate that the workflow held. The iOS router now scopes that one inspection to internal `tab.ready` and `tab.extract` reads; public requests and mutations remain gated. An isolated real-router, tab-store and WebKit regression accompanies the fix. The hosted replay is pending; the earlier simulator failures do not prove this is their sole cause. Native marker screenshots on that replay showed an iPad target-center crop with green covering 88.9% of pixels, but the opaque-era detector rejected its faded colors; the detector now checks green channel dominance while retaining the same target crop and coverage requirement. The iPhone sample's marker was about 61.5 points above the reported target center and remains a real failed observation pending replay and diagnosis. The iPhone pinch metrics showed a real scale change from 1 to 1.739 and visual width from 402 to 231, while WebKit reported its zoomed innerWidth as 231; the test now compares the visual viewport before and after the gesture, preserving the scale and clipped-center requirements. The iPad gesture remained at scale 1, so its pinch remains unverified. Fixed-enum error and bounded numeric viewport diagnostics are retained for any subsequent failure. [Hosted run 42006716721](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42006716721)

The next full hosted run at `c661062447d4fd8529896deba8d12831f4b05f4c` passed 36/44 iPhone and 35/44 iPad cases, with verified shutdown on both. Both passed the first-viewport stability, real selected-tab observation, alias-retention, and faded-marker detector regressions. iPhone also passed native pinch and the C/S motion journey; iPad's native pinch did not change scale. CSS viewport heights still changed during snapshots while native bounds stayed fixed. The differences included 34 points on iPhone and 20 points on iPad; bounded numeric safe-area and scroll-inset diagnostics are added to distinguish native inset changes from WebKit layout propagation. Both CLI calls timed out with no stdout and 96 stderr bytes; content was not retained, and G08 was not reached. Source inspection found that the hosted test approved the host CLI with a one-process-only grant, but each subsequent CLI invocation is a separate process. The 96-byte count exactly matches its expected re-pair approval prompt for the fixture address. The disposable simulator now approves and verifies the CLI's persistent exact-socket grant; the hosted replay must confirm that diagnosis. [Hosted run 42018915225](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42018915225)

## Native boundaries

* A workflow with an explicit `sessionId` fails during preflight. iOS has no existing owner-bound native session allocator for that field. The ordinary case uses the authenticated grant and selected tab.
* Navigation waits for an existing load in the pinned WKWebView to settle before reserving the next navigation token. Authorization, Stop and capture/run limits remain checked during that wait. The wait shares the action\'s existing ten-second navigation deadline; an unsettled prior load returns `NAVIGATION_BUSY` before issuing another load, with no completion uncertainty for that action. Any foreign callback after reservation still invalidates the new lease. The hosted real-WebKit regressions must verify callback retirement; `isLoading` alone is not claimed to prove it before those tests pass.
* Device capabilities advertise the exact supported typed-action set and omit standalone `press-key`. GIF and PNG capture are listed; MP4 is listed when AVAssetWriter accepts representative H.264 settings. Mobile `press-key` fails during full preflight. The public WKWebView interfaces used by Kelpie do not supply the browser keyboard default-action guarantee required by that operation. Typed text, tap and click use the documented synthetic coordinate guarantee.
* The app rechecks its paired grant using existing manual or live UOA authorization. An outbound Nessie connection does not install a script grant. The recording screen's Stop works locally. The run retains its playback lock through encoder finalization and cleanup.
* Step PNGs for a pointed action show the resolved marker before input. Other steps capture after the action. The visual viewport maps CSS points into the selected WKWebView's bounds. The same native presentation is drawn into the snapshot at the latched timestamp. Provisional navigation and a committed document each invalidate the previous presentation.
* Before admitting the first captured frame of a document, iOS waits within the existing two-second admission and capture budgets for the full native and CSS visual viewport to remain stable through the recording chrome transition. Authorization, Stop, document and pinned native-canvas checks continue during this wait. Once a baseline is admitted, the existing snapshot and same-document resize fences remain in force.

* Paced fill and type preflight every scalar plan before workflow execution. Each continuation checks the pinned target, document, viewport, focus, authorization and sensitivity; an uncertain or sensitive partial edit stops without replay. Empty paced type still resolves its target and captures its requested step screenshot without focusing or inserting text. Native iPhone and iPad runtime verification is pending.

* The enabled pointer defaults to 350 ms; an explicit duration, including the G08 fixture's 2400 ms, is preserved. A hosted native test records the default motion as a GIF, decodes all frames and checks real movement and elapsed time; its runtime result is pending.

* For movies, a pointed action holds the marker at progress zero until every requested movie format accepts its old-document frame. The app waits one requested frame interval after acknowledgement, starts the configured animation clock, then rechecks the target and dispatches. A step PNG records the pre-input point without an extra movie dwell when only screenshots are requested. A successful movie ends with an admitted frame of the final page.
* Every fixed-target result is consumed for sensitivity before result errors, document checks or callback retirement. Positive sensitivity always protects the edit. A negative result is trusted only when the helper also returns `sensitivityKnown:true`; an unknown or missing classification uses the conservative current-edit path. The common helper receives the private `refuseSensitive` policy during capture and can refuse a field that becomes sensitive during focus before setting its value. The runner registers the attempted edit literal and latches media discard independently of later error selection. Sampling stops before the existing renderer-retirement fence; final output redaction and media publication follow it. If an attempted target evaluation returns no classification, the current edit literal is registered conservatively, including without capture; captured media is discarded. This applies only after renderer evaluation starts or returns a malformed classification, not to unrelated ordinary inputs or pre-dispatch admission errors. The original error and completion uncertainty survive. Earlier named outputs are scrubbed, and a redaction failure also discards media. Active-run status has an empty artifact list, and same-owner active-run retrieval returns `ARTIFACT_NOT_READY` even with a known artifact ID. Foreign owners receive `ARTIFACT_NOT_FOUND`; older completed runs remain downloadable. The added public HTTP/MCP focus-mutation tests, four post-input password/autocomplete capture/no-capture cases, and bounded delayed-callback tests await hosted execution. Post-input cases require one observed input event: capture must refuse, discard media and stop later actions, while no-capture execution may finish with scrubbed outputs. The latter exceed the renderer deadline, wait for the original callback to retire, inspect scrubbed outputs and empty media, and verify the next run can start; they do not claim zero input.
* Stop remains available during finalization. The GIF encoder checks for Stop or a 40-second finalization budget between frames. A run already stopped during capture gets at most two seconds to write a playable GIF prefix. Status exposes authorized terminal metadata through `runSuccess` and `runError` without replaying the action.
* Registered capture files survive cleanup even when Foundation returns the same path through a different filesystem alias. Unpublished and privacy-discarded files are removed; owner-bound downloads still pass through the artifact store.

* The retained output and queued GIF source frames each have a separate disk limit equal to the requested `maxBytes`. The fixed canvas is at most 1920 pixels wide and high. There is one in-flight renderer image plus encoder working memory. Encoder backpressure can reduce frame count. Partial artifacts carry their actual encoded metadata.

## Simulator entry points

`WorkflowCaptureUITests` pairs a regular test client through the app's approval sheet. The tests serve a loopback button fixture, call the real HTTP and direct MCP endpoints, inspect the native viewport and Stop, download verified bytes and decode all three formats. The one-FPS navigation case decodes every GIF and H.264 frame, checks the green marker on the old page, checks the blue destination has no old marker, and attaches presentation timestamps and movies. Additional cases exercise implicit labels, reflected secrets, duplicate, covered and replaced targets, and a new run after capture limits. A neutral fixture isolates the pointer and colored marker in decoded GIF frames to measure the S and C paths, easing, optional wobble and fade. The step screenshot journey checks scroll readiness, enabled and hidden assertions, and centered commentary against the preceding PNG. The pinch regression uses `XCUIElement.pinch` on the actual WKWebView, records the fixture's visual viewport scale and offsets, and checks a partly visible button's clicked center against the exported marker PNG. Recording already disables page touch gestures and locks interface orientation. The native test therefore exercises pinch before playback. The common resolver tests cover scale-token invalidation; a native mid-play viewport-change result is pending a supported resize route. This new regression has passed source parsing only and awaits the common visual-viewport resolver fix and a hosted replay. Execution requires an authorized simulator. Evidence is kept as XCTest attachments. The DEBUG listener requests port 28429 on the test simulator. Reuse an authorized compatible iPhone and iPad separately.

The privacy tests inspect detailed failed workflow outputs through HTTP. Named and generic MCP play failures retain the existing `ok:false`/`COMMAND_FAILED` envelope; the tests inspect the same owner\'s terminal status for the original fixed `runError`, empty artifacts and absent outputs. Successful no-capture cases also use MCP. This does not widen gateway error payloads.

The hosted full scope also packages G08 evidence through the shared fixture and decoded-frame oracle. The paired CLI first completes its original input-and-submit journey; XCTest checks the original Count 1 title and explicitly acknowledges it before the driver navigates the same tab for fresh C and S fixtures. Each curve retains ordered Finish calibration, Start and final Finish facts, downloaded GIF and MP4 manifests and bytes, actual ffprobe timestamps, and the shared oracle report. Stage failures are retained and fail the hosted run. This adapter has passed its source and rendezvous checks, but has not yet run on a hosted simulator; native overlay equivalence remains a separate observation.

The iOS Actions workflow accepts a manual `native_workflow_tests=true` input. On a dedicated `macos-26` runner it builds the shipping native dependencies, app, tests and CLI, then selects an existing compatible iPhone and iPad from the installed simulator inventory. Devices run sequentially. A paired CLI uses typed inputs, requests all three capture formats and checks downloaded hashes. The XCUITest approval sheet authorizes the host CLI separately from the HTTP test client. The job records the revision, app binary hashes, installed-device hashes, toolchain, XCTest results, attachments and CLI media. The workflow artifact contains simulator evidence. Before the first dispatch, all changed Swift test files passed parsing, repository SwiftLint passed across 322 files, and the YAML, embedded shell commands, manifest scope and Python selection checks passed. The driver accepted the existing generated test configuration and refused execution on the development Mac. The first hosted build at `444ea3e832f03bd35d5218caba8a063d669426e0` reached the UI test bundle and stopped because Xcode 26 rejected the legacy CGRect string formatter in the diagnostic attachment. The attachment now uses Swift's standard string conversion. The first run produced no device or media results. [Hosted build 41956928725](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41956928725) [Hosted Mac runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)

The corrected hosted run built the app, all test targets and CLI at `2e08956fa0f1a67bbf05b533efac5eb05b5ba0b7`. It selected an iPhone 17 and iPad Air 13-inch (M4), both on iOS 26.5. The iPhone began XCTest scheduling, then expired simulator container lookups and cleanup prevented a complete result bundle. The iPad run was withheld. A nonce-scoped loopback fixture now carries the public tab ID and completion state directly between XCTest and the CLI driver, without querying simulator containers while XCTest is running. Primary errors and cleanup outcomes are preserved separately. [Hosted run 41957712925](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41957712925)

The third hosted run at `2cde738ab3a6bcad1369e08a7dc1594f078d9bb8` built the app and completed 19 iPhone tests. All six admission tests passed. All 13 UI journeys reached pairing and failed during initial workflow navigation with `NAVIGATION_REPLACED`, so no capture or user-flow pass is recorded. The original XCTest result and 138 MB artifact are preserved. Native screen recordings show the app and ordinary pairing sheet; they are XCTest evidence, not exported workflow movies. Xcode left the selected simulator shut down. The driver's subsequent container lookup failed with SimError 405, and a redundant shutdown command incorrectly prevented the iPad run. The driver now records installed hashes before XCTest, reads the test summary first, verifies the known installed path after shutdown, and accepts an observed shutdown without a second mutation. Four isolated cleanup tests cover that state, a concurrent shutdown, uncertain container lookup and refusal to terminate a different binary. [Hosted run 41962306095](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41962306095)

The navigation reservation originally preceded asynchronous grant authorization and registered the issued token through the handler context. `IOSWorkflowNavigation.issue` now authorizes first, then reserves and records the exact pinned view synchronously. A focused harness using the production document and lease classes reproduced invalidation by a prior provisional callback during authorization, then passed the corrected ordering, exact-token acceptance, foreign-navigation rejection and revoked-grant case. The app replay is pending. Initial fixture navigation now throws on failure so dependent UI checks cannot continue with an unprepared page.

The fourth hosted run at `c71aeabd513c4d19c5088cbae7202cd59fbb95f6` verified identical installed hashes before and after testing on both devices. Each device passed eight admission tests and failed all 14 UI journeys during initial navigation. One iPhone case timed out; the other 27 failures reported `NAVIGATION_REPLACED`. Cleanup verified shutdown for both devices. The authorization-ordering hardening therefore has not resolved the observed WebKit failure. The 260 MB result artifact preserves both complete XCTest reports and native screen recordings. [Hosted run 41967313412](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41967313412)

The manual workflow now accepts `native_workflow_scope=navigation` alongside `native_workflow_tests=true`. The default remains the full corpus. The initial diagnostic selection ran three cases per device: real WKWebView HTTP navigation through the production coordinator, that navigation with a prior blank request, and the paired app's new-tab workflow navigation. The first two reuse the same loopback fixture as the UI tests. DEBUG builds record one fixed-enum lease invalidation reason and a fixed wait/timeout state, without document versions, token identities, URLs or page content. The driver writes only those allowlisted events to `navigation-lease.json`; it excludes raw exported system diagnostics from the evidence directory. The current selection adds delayed prior HTTP, cancellation, exhausted deadline, foreign callback and a cold public-API admission case, for eight cases per device. Its bounded test phase is ten minutes to include cold XCTest startup and teardown; the preceding six-minute iPad phase ended before xcodebuild retired. Other workflow capabilities remain pending during this diagnostic selection.

The navigation-only run at `8a2ecc5571e64e4bce872c3ef2cc130c5c561458` passed one of three iPhone cases: a fresh WKWebView loaded the HTTP fixture with the expected navigation token. The prior-blank case and public app navigation failed. The fixed diagnostic recorded `unexpected-navigation-token` for both failures, and the public wait reported the same state. This isolates a prior-load sequence; it does not identify the mismatched token itself. The iPhone's installed hashes matched before and after testing. The iPad exceeded the six-minute test phase; its partial test log also reports prior-blank and public navigation failures, but no completed suite denominator or post-test hash is claimed. Both devices were verified shut down during cleanup. The debug implementation hash was `b4f049ed3d82dae5665be80a3e0c967dae88b3642a2c91aeaaa476ebccdc6781`; the 123 MB artifact retains the results and attachments. No captured workflow media or other UI capability passed in this diagnostic run. [Hosted run 41971410277](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41971410277)

The next focused run, `41976933561` at `b927cb999509e25e3c85f3012620713b736dc73a`, passed six of seven cases on each device. Public paired navigation, fresh WebKit navigation, the exact prior-blank callback retirement assertion, cancellation, deadline refusal and rejection of a foreign callback all passed. The delayed prior-HTTP case failed on both devices after about 10.3 seconds. Its legacy XCTest error record identifies `Gestures.GesturePhaseQueue<()>.InvalidTransition` during deinitialization, not a reported `NAVIGATION_REPLACED`; no prior-lease attachment was reached. The underlying operation failure remains unresolved. The one unexpected-token diagnostic per device belongs to the intentional foreign-navigation case. Both devices retained matching installed hashes and verified shutdown. The debug implementation hash was `9d713ed35f9fb99469a388f33320ac5dac1ab7e03bbc11066265d93c962c6529`. The 126 MB artifact preserves complete reports and native PNGs; visual inspection confirmed the real fixture and native browser chrome on both devices. These images prove navigation only, not marker or exported-media behavior. The report SHA-256 is `ba687252047f57d9b45a64303fb13bb940ea61e78b7549b40358a80aa7b9e147`. [Hosted run 41976933561](https://github.com/UnlikeOtherAI/kelpie/actions/runs/41976933561)

The fixture now explicitly retains its unattached UIKit container and coordinator across asynchronous work, and attaches the typed primary error, fixed stage, loading flag and elapsed time before teardown. The controlled delayed-HTTP case first completes an owned same-view HTTP warmup outside the production navigation budget; its actual prior callback and new lease must still pass the unchanged checks. A separate cold public-API case accepts only successful navigation or `NAVIGATION_BUSY` with no destination request and no completed action. After a busy refusal it waits for the prior page to finish naturally, then issues a new normal API navigation. Complete bounded HTTP request-line accounting verifies that the refused destination was not loaded. A standalone check of the actual fixture source passed with two concurrent loopback fixtures, delayed responses, and an incomplete request that received no response until its remaining line arrived. Swift parsing, repository lint and driver tests pass. The hosted lifecycle failure is not considered resolved by these source checks; the next full 39-case/device run must verify the condition and retain any primary failure.

## Generic simulator build

At base `9b939695`, the Mac built the generic arm64 simulator C++ libraries from this checkout with deployment target 16.0, local LLM enabled, native tests disabled and one compiler. The CMake configuration generated the current browser contract from a frozen dependency install. The build log contained zero compiler warnings. After merging the Apple codecs, redactor and strict status contract on base `ad60fd40669cddbf0b10ff67f86eec80dbe03290`, the app relinked the shared native code, passed `make lint-swift` with zero violations and generated its project with Tuist 4.180.0 using `--no-open`. Xcode SDK 27.1 built the app and both test bundles for a generic arm64 iOS simulator at minimum iOS 16.0. Product version was 0.1.21. The exact pre-documentation source tree was `25fb50b8e1b4c9ebcabc6f793511b007deef02d7`.

The build ran `xcodebuild build-for-testing -project apps/ios/Kelpie.xcodeproj -scheme Kelpie -destination 'generic/platform=iOS Simulator' -configuration Debug -jobs 1` with private DerivedData and signing disabled. The executable SHA-256 was `e1bf76dbde60f93025c18027f62cabf181d8495167ed143966fb305d39f3b0b7`. The implementation in `Kelpie.debug.dylib` had SHA-256 `32805960c3ae72f47f4cd567c65060f1e40d300917263fdc12534aed2a64d521`. No simulator was launched. The cold build reported three warnings in AppReveal revision `5d6d16d67a7cd08069f3d69c2d484249e2ed8485`, XCTest framework deployment warnings from SDK 27.1, and skipped intent metadata in the test graph. Kelpie Swift sources emitted zero compiler warnings. The installed build and device evidence require separate records after the native MCP registry change.

At integration base `419bc2cad3a5b72d1e25a032bfb4e5a4aaaf209f`, the app rebuilt the current contract and native registry from source with the shared Apple gateway policy. Strict SwiftLint found zero violations across 311 files. Tuist generated the project without opening it and the incremental generic arm64 build-for-testing passed. The app minimum is iOS 16. The test targets use iOS 17, the minimum supported by the pinned SDK's XCTest and XCUIAutomation frameworks. The two test bundles reported skipped AppIntents metadata extraction. This incremental build emitted no compiler or linker warnings. The pre-evidence tree was `57c682eed839fea57e0e75a43fd1b5a3daa89aa4`. The executable SHA-256 was `e1bf76dbde60f93025c18027f62cabf181d8495167ed143966fb305d39f3b0b7`; the debug implementation SHA-256 was `46e1c5fdd02c89177bff47cac421ce6bafb88ba2cb11fc851c2c16d1d8c5a1ad`. Simulator execution and inspection of the exported app media are pending.

## Active scripts and viewport layout

An active script retains the existing Stop control, input blocking, orientation
lock and lifecycle checks. GIF or video capture and legacy playback use the existing immersive
viewport. No-capture workflows, automatic screenshots and explicit PNG actions
keep the normal browser viewport and chrome while the existing Stop control
is visible. Normal chrome is disabled and hidden from accessibility during the
run, and existing address focus is retired. Loading and scroll-driven chrome
changes cannot resize an active non-movie viewport. A staged iPad view stays in
the same hierarchy while its active clip is square.

The hosted presentation-mode test checks native Stop, disabled chrome and the
WebView frame before, during and after each non-movie mode, and checks that GIF
and video still use the immersive state. Additional controls cover address focus,
real delayed loading, scroll, and the iPad staged viewport. It retains screenshots
for both device families. Device results are pending; source checks alone do not establish these
behaviors or the keyboard transition policy.

## Release prerequisites

On 5 November 2026 the project declared `com.unlikeotherai.kelpie`, team `59S95D279D`, and app version 0.1.21. The iOS CI job builds an unsigned generic simulator app. The repository release workflow has no iOS device archive or TestFlight publication job. The Mac's local signing inventory contained two valid development identities and one valid Apple Distribution identity across teams. The distribution certificate's team did not match the project team. Of 43 installed provisioning profiles, one current wildcard development profile matched the bundle and team. There was no matching local ad-hoc or distribution profile. The audit inspected certificate and profile metadata only.

A reproducible simulator archive needs its own source version, hash, publication and install check on an authorized compatible simulator. A device archive needs an appropriate distribution identity/profile or an authorized managed signing path and a compatible physical install target.

See the [public workflow contract](../../api/script-workflows.md) for the CLI, versioned actions, artifact retrieval and host secret binding.

## Hosted mobile check: 42125528359

The hosted `mobilecheck` run exercised revision
`9d88078c736e203f1d03a5d50273f6810906ddb7` on an iPhone 17 and an
iPad Air 13-inch (M4), both iOS 26.5, with Xcode 26.6. The iPhone passed
14 of 15 selected methods and the iPad passed 12 of 15; all required methods
were present and both simulators were verified shut down. The retained artifact
is [ios-native-workflows-9d88078c](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42125528359).

On both devices, the delayed-navigation Stop control returned
`SCRIPT_ABORTED` with `mayHaveCompleted: true`. The no-movie loading and
scroll viewport controls, baseline-coordinate chrome and address blocking,
presentation modes, marker lifetime and retirement, paired MCP click and
decoded media, and five selected unit controls passed. The staged-tablet
viewport control passed on iPad; its iPhone method returns before exercising a
tablet stage. These results do not cover the full corpus, CLI, or G08.

The iPhone clipped-pinch action returned `TARGET_NOT_FOUND`. Its fixture
reported a visual-only intersection, but the button was outside the BODY
overflow clip and the purported intersection did not hit the button. This is
a correct refusal for that measured fixture, not proof of a visible-target
failure; the separate scrollable pinch control passed. Both iPad pinch controls
remained at native and visual scale 1, so neither proves pinched behavior.

The iPad same-scene marker image did not contain the marker. XCTest began its
accessibility target lookup at 1793920737.266 and retained the screenshot at
1793920781.591, after the configured four-second marker lifetime. The click
result was centered, but this image cannot establish live marker projection.
The earlier 421190 run passed that same-scene control on both devices. The
42130731818 geometry replay is separate and its outcome is not included here.

## Hosted geometry check: 42130731818

The focused `geometry` run exercised revision
`12123d02f4cd53c8b381faa664481bc59de791ab` on the same iPhone 17 and
iPad Air 13-inch (M4), iOS 26.5 and Xcode 26.6. The iPhone passed seven of
nine selected methods and the iPad passed five of nine. All methods were
present, and both simulators were verified shut down. Its retained evidence is
[hosted geometry 42130731818](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42130731818).

The same-scene native marker projection passed on both devices. The iPhone
calibrated partial target had a 50 CSS-pixel hit-testable intersection; its
single tap hit the expected center and its step PNG marker passed. A separate
clipped, unhittable target returned `TARGET_NOT_FOUND` with no click. The
iPhone scrollable native pinch control passed. The iPad paired MCP click and
decoded-media control passed.

All three iPad pinch cases remained at visual and native scroll zoom scale 1.
The scoped observer on the same native view and document recorded one began,
18 changed and one ended event, with recognizer scale reaching 1.8605 in the
scrollable case; this proves gesture recognition but does not establish why
WebKit did not change page zoom. The standalone observer unit did not arm on
either device, so its view/document retirement assertions were not proven by
that fixture. The live observers did arm and bind to the same view/document.

The iPhone paired MCP run failed `CAPTURE_VIEWPORT_CHANGED`. Run-wide
diagnostics contain one snapshot mismatch from CSS/layout 402x812 to 402x778
with native bounds 402x874 and unchanged safe/adjusted inset tuples. The
retained diagnostic is aggregated and cannot establish which test emitted it
or whether a baseline or target binding existed. No capture fence was changed.

## Hosted geometry check: 42134918643

The focused `geometry` run exercised revision
`9cd08d9e834a07aa067ca85ef04c3ad87fd9fd3c`, source tree
`6d32a50a198b6e5f2a7ee054aa819934f5b72f1d`, on iPhone 17 and iPad Air
13-inch (M4), iOS 26.5, system WebKit and Xcode 26.6 (17F113). The simulator
executable SHA-256 was
`e9a0b1b2fac00cf5f11f4205048e126e799b4760a9ab2e0ec431eae474e7ee8d`;
its debug dylib was
`54cb0ca55b1ec04167a41d41e6f843fc5b3550a2560cdc7b1184d6e013cd9b16`.
The AppReveal source revision was `5d6d16d67a7cd08069f3d69c2d484249e2ed8485`.
[The hosted run](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42134918643)
retains the device evidence.

The iPhone passed nine of ten selected methods: the observer unit, three
viewport units, live marker projection, calibrated partial target and step
PNG, clipped target refusal, and scrollable pinch passed. The iPad-only
comparison method returns early on iPhone. The paired MCP capture failed
`CAPTURE_VIEWPORT_CHANGED`. The run-bound failure attachment contained
`non-snapshot-or-unavailable`, not a baseline or target-bound snapshot
tuple. One run-wide `native-insets` event recorded 402x812 to 402x778 CSS
geometry with native bounds 402x874; it is not bound to that paired run.

The iPad passed seven of ten selected methods, including the same-scene
marker, paired MCP and decoded media, four unit controls, and the scoped
content-mode comparison. The three ordinary default-mode pinch methods stayed
at visual and native scale 1; the clipped-refusal method also recorded test
termination. Both default and test-only mobile content modes used exactly
`width=device-width,initial-scale=1`; the mobile preference was confirmed
applied only to the owned loopback navigation. In each mode the owned
recognizer began, changed 18 times, ended, and reached scale 1.8605 while the
native and visual page scales stayed 1. This comparison does not justify
changing the app's default content mode or prove positive iPad page zoom.
All required methods were present and both simulators were verified shut down.

## Hosted geometry check: 42139243267

The hosted `geometry` run used revision
`11310fe3c3bf7cefc8071f3fc34782c645b80edf`, source tree
`09d4e98a8d75ce67f806a784d27ac5ee4f69b2ca`, Xcode 26.6 (17F113) and
iOS 26.5 on iPhone 17 and iPad Air 13-inch (M4). The simulator executable
SHA-256 was `e9a0b1b2fac00cf5f11f4205048e126e799b4760a9ab2e0ec431eae474e7ee8d`
and its debug dylib SHA-256 was
`1dc209ad5dd8f7f7b0d6ba3a98104697161eb0f97ca72ddff6f9e7ceef162387`.
The AppReveal source revision was `5d6d16d67a7cd08069f3d69c2d484249e2ed8485`.
[The hosted run](https://github.com/UnlikeOtherAI/kelpie/actions/runs/42139243267)
retains the evidence. All 12 selected methods were present on each device,
and both simulators were verified shut down.

The iPhone passed 11 of 12 methods. Five viewport, observer and evidence
ownership units, same-scene live marker, calibrated partial pinch and PNG,
unhittable target refusal, and scrollable pinch passed; the two iPad-only
comparison methods return early on iPhone. Paired MCP capture failed
`CAPTURE_VIEWPORT_CHANGED`. Its exact run-bound receipt reported site
`native-viewport`, an established same-document baseline, and no target
binding. Before and after native bounds were 402x874, DPR 3 and scale 1;
layout/visual height changed 812 to 778 and derived content rect changed
[0,62,402,812] to [0,62,402,778]. The receipt did not bind raw adjusted
inset values. The same-document post-baseline refusal remains in force.

The iPad passed nine of 12 methods: the same five units, same-scene marker,
paired MCP and decoded media, and both diagnostic comparisons. All three
ordinary pinch cases remained at page scale 1. On the same owned view and
document, a recognizer began, changed 18 times, ended, and reached 1.8605 in
each of the no-viewport-meta and explicit
`width=device-width,initial-scale=1,user-scalable=yes,maximum-scale=5`
fixture variants; native and visual scale remained 1. The separate default
versus test-only mobile content-mode comparison likewise stayed at scale 1.
These controls do not prove positive iPad page zoom and did not change app
viewport policy.
