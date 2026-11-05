# macOS automation capture

## Scope and revision

- Owned worktree: /Volumes/External/Projects/kelpie-worktrees/capture-macos-20261104
- Branch: codex/capture-macos-20261104
- Original draft base: c01b2038bdb663cb9d5c7add134d587635da17ca; current integration prerequisite: 84b886b6333f741ac72adf2acc49e58189743e71
- Platforms required: macOS WebKit and CEF.
- Status: shared codec/redaction/gateway helpers checked; complete macOS adapter is in progress. Swift lint, exact native-core relink and Tuist generation passed. Full app compilation and installed WebKit/CEF flows remain unclaimed. Computer Use is disabled; no existing app process has been replaced.

## Existing behavior and defect

ScriptHandler forwards action dictionaries to existing routes, supports local Stop and remote abort/status, and writes screenshot responses to temporary files. It has no GIF/video encoder or remote artifact retrieval. HandlerContext injects temporary DOM markers. RendererEngine.takeSnapshot captures the renderer; CEF normally takes its accelerated surface, which excludes native overlays. Saving that image alone cannot prove a native marker appeared in exported media.

## Implementation

ScriptPresentation renders a hit-test-transparent NSView scoped to the renderer. Pointer motion is presentation only and does not send hover events to the page. Capture composites that same marker/pointer model into renderer frames. It does not depend on screen-recording permission or external ffmpeg.

ScriptCapture bounds PNG intermediate frames separately from retained outputs; the shared streaming GIF encoder admits complete frame units under the aggregate output cap. ScriptVideoWriter uses AVAssetWriter for MP4/H.264. Dimensions are even and bounded; the initial viewport is fixed. Resize terminates capture with CAPTURE_VIEWPORT_CHANGED. A document change during snapshot refuses the mixed frame. Between documents, previous markers are cleared. Encoder backpressure drops presentation frames and retains monotonic timestamps.

ScriptArtifactStore returns opaque IDs, SHA-256, MIME type and bounded chunks. It retains no public file paths. Download requires the immutable authenticated transport owner copied at admission. A listener incarnation, authenticated client and bearer digest form a private owner scope; neither digest nor authority is supplied by request JSON. Rotation makes old artifacts inaccessible. Revocation is enforced by normal transport authentication before each request. Outbound Nessie requests without admitted owner context fail closed.

## Input guarantee

RendererEngine exposes evaluateJS/evaluateBrowserControlJS and makeView, but no trusted pointer injection. Existing InteractionHandler.tapScript uses elementFromPoint and synthetic MouseEvent/PointerEvent sequences. New shared semantic dispatch must atomically recheck target identity, document, visible eligible bounds and hit-tested center before synthetic coordinate dispatch. Its guarantee is synthetic-coordinate, never trusted OS input. Presentation sends no pointer events.

## Verification checklist

Unchecked items are requirements, not completed evidence.

- [ ] Generate Tuist project, lint Swift, build with no warnings.
- [ ] Record exact tested revision, macOS version, WebKit/CEF versions and executable path.
- [ ] Stop stale Kelpie only after window/resource ownership is granted; launch one known candidate.
- [ ] Direct HTTP and direct MCP: strict v1 script, semantic button/label resolution, visible center dispatch.
- [ ] CLI MCP alias: same script and bounded artifact download.
- [ ] Unique target success; missing, duplicate, obscured, disabled and moved target refuse before dispatch.
- [ ] Navigation and resize during presentation refuse stale coordinates.
- [ ] Native pointer S/C curve, ease in/out; no hover change from presentation.
- [ ] Circle color/radius/wobble/fade appear in native view and exported screenshots/GIF/MP4.
- [ ] Decode and play GIF and MP4, inspect timing and overlay frames.
- [ ] Step screenshot taken before marker disappears.
- [ ] Local Stop and same-owner remote cancel finalize playable partial outputs.
- [ ] Another owner, rotated/revoked grant and listener restart cannot read/status/cancel a run.
- [ ] Failure during encode clears recording UI, preserves terminal metadata and allows next run.
- [ ] Duration/byte budget, encoder backpressure, viewport resize stay bounded and truthful.
- [ ] Match before/after screenshots only for visibly changed states, on actual base and final revision.
- [ ] Repeat the relevant flows on WebKit and CEF.

## Commands and evidence

Source-only focused SwiftLint was run on the four initial capture modules. Initial formatting issues were corrected. Full lint, generated build, XCTest and manual native verification remain pending resource ownership and shared contract integration. No screenshots or playable outputs have been claimed.

## Source checkpoint (not a native verification result)

The strict adapter is drafted against kelpie_browser_validate_script and kelpie_browser_script_target_expression, pending the shared generator/native ABI commit. It preflights before acquiring playback state. fill/type use shared atomic identity-bound editing; assert/wait-ready use shared observation mode. press-key is explicitly refused in full preflight because the current Mac renderer exposes no supported key-dispatch method; synthetic KeyboardEvent does not implement browser default actions.

HTTPServer establishes a private TaskLocal owner only after normal authentication. V1 copies this owner before awaiting. Legacy callers cannot reset the v1 owner while it is active. The recording gate remains held through encoding and final cleanup. GIF final encoding runs off MainActor so native Stop remains responsive. Current tests cover chunk ownership/ranges, deterministic path endpoints/bends and the finalizing gate, but have not run because native compilation remains held.

Focused SwiftLint passed on the changed Mac source checkpoint. No native build, XCTest, live HTTP/MCP, export playback or UI success is claimed. No commit has been made while required checks are pending. Source remains safely in the assigned worktree.

## Adapter invariants and remaining evidence

A versioned workflow is fully validated before admission. Supplied session IDs are refused with SESSION_UNSUPPORTED before any action until a real native owner-bound resolver exists. Admission acquires the existing browser lease and recording gate atomically, then releases the short lease for canonical inner extraction/readiness. Pending renderer callbacks retain the same fence until actual completion or renderer termination; uncertain input is never replayed.

Frames use script-only renderer capture: WebKit native snapshot callbacks, Chromium fixed Page.captureScreenshot commands. There is no OS-window crop, shell resize or cached-view fallback. The initial native and CSS visual viewport is fixed; resize or document transition during a sample refuses the mixed frame. The native overlay and exported overlay share one numeric drawing model.

At low FPS a real marker is held at progress zero until the next legal movie sample admits it. Its fade clock starts only after admission, followed immediately by exact token/document/viewport recheck and atomic synthetic-coordinate input. This dwell is internal, cancellable and absent for screenshots-only runs; it does not add a public timing field. Complete GIF/MP4 all-frame pixel evidence, especially a movies-only one-FPS navigation, remains required.

Every explicit screenshot step produces PNG even without a capture block or when authored formats only request GIF/video. Only the originally requested screenshots format enables automatic per-step PNGs. Pointed automatic PNGs occur before input with the native marker; other steps occur after their action.

The app links inference through the existing pinned native CMake llama bootstrap, not unidentified vendor binaries. Darwin enables CPU/Metal/Accelerate; other platforms keep their existing backend defaults. Actual ai-status and small supported inference smoke remain required after app handoff.

The MAC-APP-BUILD-1 helper resource admission initially printed saturated CPU readings but incorrectly proceeded to its bounded codec check. That check passed; it is not evidence that the admission rule was respected. Subsequent phases fail before any command unless all three CPU samples show at least 30 percent idle and memory has headroom.

## First complete compiled candidate

At source prerequisite bb12bf7e plus this adapter, macOS 27.0 / Xcode 27 SDK compiled both renderer paths and the XCTest target with build-for-testing, one nice-10 compiler. Full make lint-swift passed for iOS and 322 Mac files; Tuist generation used --no-open. Native CMake rebuilt all six core libraries from this worktree. The first app attempt stopped at missing Swift module llama; a permanent thin module map now imports the pinned bootstrap headers and the rebuilt candidate succeeded. Build logs are retained under .cache/mac-app-build.

The native dependency is llama source 8345f333951c661d166b00e6f9362e553768f292. GGML_METAL and GGML_BLAS are ON only for Darwin; iOS/Windows/Android/Linux retain OFF. CEF header and linked framework both report 149.0.6 / Chromium149.0.7827.201; existing CEF148 assets were not reused. AppReveal uses clean committed source3a28e56e5e72aa2a1f0b241cac63140e5906c8b4, without another worktree's dirty edits.

Warnings remain in unchanged AppReveal concurrency declarations, existing native categories/callbacks, deprecated UI calls, build phases without output declarations and the optional absent Gecko helper. The new ScriptCapture category declaration matches its implementation and no new workflow-file warning was reported. This is not a warning-free release claim.

No XCTest has executed and no app has launched yet. The known candidate is apps/macos/.build/Build/Products/Debug/Kelpie.app. Existing favorites app12718 and DeviceHub545 remain untouched. Actual owner-authorized app handoff, WebKit+CEF forms/extraction/readiness/session refusal, exact-socket CLI/MCP transfers, low-FPS all-frame GIF/MP4/PNG inspection, Stop/failure recovery and ai-status/inference smoke are still required. Named MCP script profile enablement is coordinated with the common registry owner after this checkpoint.

## Runtime plan after authorized app handoff

Computer Use stays off. Stop/replace favorites app12718 only after its owner hands over; reuse DeviceHub545. Pin the exact candidate executable/framework revision and one known listener before sending any command. The DEBUG app-owned AppReveal server on8421 provides documented list_windows, screenshot, tap_element and click_menu_item; failed bind or ambiguous target means no native-UI proof.

1. Pair through the normal UI with app-owned controls, then exercise direct protected HTTP, named/generic MCP and the CLI against that same pinned socket/grant. Capture state/status before play and verify explicit supportedVersions admission. Old/legacy active status must block v1 admission and recover automatically after legacy finishes.
2. Run WebKit and Chromium separately on a fixture with role/name, label, selector, clipped and ambiguous targets. Prove exact hit coordinates and field identity from fixture events; retry no uncertain mutation. Cover changed/obscured/replaced targets, viewport/document changes, hidden tabs, readonly/password fields, foreign session IDs and unresolved inputs before earlier mutations.
3. Exercise S/C movement, ease endpoints, configured color/radius/wobble/fade and presentation-only hover behavior. With wobble/fade disabled for a stable pixel comparison, capture the actual native overlay through the supported AppReveal screenshot and match its center/color/extent to decoded exported PNG/GIF/MP4 frames on the same document. Record timestamp and viewport mappings; unavailable native pixel source leaves this proof pending.
4. For each engine, run one-FPS movies-only navigation and all-formats navigation. Decode every GIF and MP4 frame and inspect the tap-colored region on the pre-navigation fixture document. Each requested successful movie must actually retain the critical marker; a raw-buffer acknowledgement alone fails acceptance. Check post-navigation document colors and ensure no later annotation fabricates pre-navigation evidence.
5. Verify screenshot-only defaults, explicit screenshot with GIF-only formats, automatic per-step PNG selection, screenshot-only duration expiry during a wait, FPS/dimension/duration/aggregate-byte caps, finalization byte refusal, cancellation, valid partial prefixes and a successful subsequent run. Any failed finalization must report failure/partial without claiming a guaranteed successful output.
6. Use native Stop through its app-owned UI identifier while sampling/finalizing; verify public metadata-only status remains responsive and same-owner artifact chunks recover actual bytes. Try foreign bearer/listener/run/artifact IDs, malformed offsets, revocation and interrupted downloads without leaking paths, outputs or secrets.
7. Exercise canonical readiness/assertions and named structured extraction/provenance, then compare direct HTTP/MCP/CLI output. Demonstrate sensitive input refusal/redaction, including short secrets and dynamic output keys, with no literal or reflected secret in public status/errors.
8. Query actual ai-status, load the smallest already-supported model through existing controls, run a bounded inference smoke with the pinned CPU/Metal/Accelerate graph, and unload through supported APIs. No unidentified vendor library substitutes or inference-disabled success are allowed.

Focused active-capture deadline regression is reproducible with bash scripts/testing/apple-script-deadline.sh. It verifies exact limit admission, refusal immediately beyond the limit, invalid elapsed values and separate stopped/finalization grace. The running workflow now checks this independently of whether a continuous movie sampler exists.
