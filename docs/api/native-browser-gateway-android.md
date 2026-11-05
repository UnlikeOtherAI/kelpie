# Android browser gateway

## Release signing

Android release packaging uses local Gradle signing, including on GitHub runners.
The release job requires `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` before contract generation or native
builds start. Store the proper Kelpie release identity outside the checkout; the
runner decodes it into a private file under `RUNNER_TEMP` and removes it on exit.
Credentials are never included in artifacts or repository files.

Gradle must produce `app-release.apk` and `app-release.aab`. The workflow verifies
the APK with Android SDK `apksigner`, and requires `jarsigner` to confirm a signed
App Bundle before copying either output to release staging. Missing configuration,
unsigned outputs and failed signatures stop the Android job; there is no unsigned
or debug signing fallback. Existing isolated debug APKs are test artifacts only.
Signing ownership must be approved before creating or replacing a release identity.

## Native gateway

Android exposes authenticated `POST /v1/browser-control` and `POST /mcp` through
the existing Ktor listener, pairing bearer policy, header validation and body
bounds. Pairing still requires on-device approval. Kotlin drives authorization
and native dispatch; schemas, compact catalogs, extension descriptors, references
and uncertainty come from `native/core-mcp` through JNI.

Protocol failures return HTTP 200 with their canonical/MCP error envelope so
clients retain uncertain outcomes; authentication, body and recording admission
failures retain their transport error status. Page dispatch rechecks the requested
active tab on the main thread and keeps that admitted WebView across suspension.
The renderer comes from the active tab object, avoiding a delayed UI cache.
Navigation waits for a complete replacement document, including same-URL reloads,
while preserving redirects and same-document fragment changes; an old complete
document cannot prematurely settle a reload.
MCP notifications receive an empty HTTP 202 response. Authenticated GET returns
405, unsupported protocol-version headers return 400, and browser Origin headers
are refused under the existing native-client boundary.

The direct MCP catalog has four tools: `kelpie_browser_control`, `kelpie_extensions`,
`kelpie_extension_tools`, and `kelpie_extension`. Extension availability follows
registered, supported Android handlers. Rich inference/recording remain available
through their discovered extension schemas and their existing HTTP entry points.
An outer inference/recording MCP invocation uses an ephemeral native handle and
its existing provider/run deadlines; it does not hold the browser lease while
waiting for model output. Inner renderer calls retain normal serialization, and
cancellation/status extensions remain reachable. The per-run model catalog
excludes recursive inference extensions under its existing semantic permissions.

The existing OpenAI-compatible browser agent uses a gateway per run, the same
compact catalog and its task-list tool. Its rich extension admission retains the
existing semantic read/click/fill/select/check permissions. Navigation, arbitrary
evaluation, screenshots, cookies, storage and tab creation/closing remain outside
that inference scope. `allowActions:false` removes common mutations. Read-only
inference refuses an inactive target; action-enabled inference can select it
initially. Every operation rechecks the pinned active tab and both canonical
`tabId` and extension argument `tabId`. Plain OpenAI and embedded GGUF inference use bounded common snapshots against a captured owned renderer, including requested background tabs without selection. Full caller history is retained; public text/accessible names and truncation form the observation, with form values omitted. GGUF does not acquire an agent loop.

One coroutine mutex serializes complete gateway transactions and ordinary legacy
browser operations across HTTP, MCP and inference. Legacy mutations invalidate
all live sessions; common mutations invalidate other live sessions as well. Main
frame navigation queues per-tab invalidation before the next transaction. Script
playback owns its nested handler sequence; abort/status and inference cancellation
remain reachable during playback. Recording gates still refuse browser operations.
Renderer dispatch is bounded at 30 seconds. Cancellation resets native state and
preserves its uncertain outcome, without an automatic repeat. An uncertain action
stops the current agent run. The shared mutex remains held until the original
renderer callback completes or that WebView is destroyed; a later explicit
observation can then reconcile without restarting the app. Per-run handles close
after inference; Activity teardown closes remaining handles after the listener.

The fixed reader uses `WebView.evaluateJavascript` in the page realm; this binding
has no private DOM content world. Ephemeral object identity detects ordinary stale
or replaced nodes, but page scripts can observe or interfere with that registry.
This is a correctness guard, not hostile-page isolation. Common ref actions use
fixed DOM activation/append semantics in the same realm; rich interaction
extensions retain their existing events. Android has no registered native keypress
handler, so common keypress is omitted. Common screenshots support viewport PNG;
the rich extension retains its formats and full-page options.

Build on Ubuntu with Java 17, Android SDK, Node 20+ and pnpm in PATH:
`cd apps/android && ./gradlew build`. CMake generates the common contract from
shared sources and links `kelpie_core_mcp` into `kelpie_jni`; schema copies are
never committed. JVM tests cover authentication, scope, serialization, refusal,
timeout/cancellation and ownership. Native CTest covers canonical validation and
ref lifetime. Emulator verification exercises JNI and the real HTTP/MCP renderer
path separately; an emulator pass does not establish physical-device acceptance.

For the real journey, install this revision's APK on an isolated emulator and set
`ANDROID_SERIAL` to its explicit serial. Forward host 18420 to device 8420, then
run `python3 scripts/testing/android-browser-gateway.py --adb "$ANDROID_HOME/platform-tools/adb"`.
The fixture server binds host 18421, and the harness taps the existing **Yes, once**
pairing approval UI. It verifies JNI observation/actions, ref expiry/replacement,
extension discovery, renderer timeout retirement, and the actual OpenAI agent
catalog/admission/uncertainty stop using a local mock endpoint. It also runs the
standard MCP SDK initialize/list/call journey from the CLI's installed dependency.
Bearer contents stay in memory and stdin; no persistent pairing is created.

## Typed script capture

Android has a strict opt-in version1 script implementation beside the unversioned
legacy handler. It consumes shared validation, target resolution, presentation and
bounded redaction through JNI. Native relink, public HTTP/MCP discovery and real
phone/tablet acceptance remain pending; see
[Android verification](../plans/browser-automation-capture/android.md).

Version1 pins the selected foreground WebView under the existing authenticated
grant. Supplied sessionId fails full preflight with SESSION_UNSUPPORTED. Mobile
press-key also fails full preflight because matching verified keyboard defaults
are unavailable. Target input reports synthetic-coordinate.

The same native overlay draws into the live container and exported step PNG,
animated GIF and H.264 MP4. GIF preserves the requested marker color and quantizes
other pixels; MP4 requires an available native AVC encoder. A shared retained-byte
budget covers outputs. Bounded backpressure can drop continuous frames. Stop,
foreground loss, revocation or tab replacement finalizes partial outputs where
possible. Finalizing remains active until codecs and renderer retirement finish.

Status exposes safe metadata only: success describes the query, runSuccess the
terminal result, and runError a fixed safe failure. Only direct play returns bounded
redacted outputs, after a current authority recheck. Artifacts have opaque owner/
grant/listener-bound IDs, bounded chunks and hashes, never arbitrary paths or URLs.
Lightpanda stays desktop orchestration; WebMCP requires a real API and explicit
grant. A Nessie connection alone cannot grant recording permission.
Semantic tap/fill/type step PNGs represent the pre-input marker on the original
document; other step PNGs represent post-action state. Movies hold marker phase
zero until actual encoded admission and one requested sample interval, then start
the configured animation before exact target recheck and input. Navigation clears
the old-document overlay. Screenshots-only and uncaptured scripts have no extra
marker dwell. Those runs retain the normal viewport and browser chrome while Stop, input blocking and orientation lock remain active. GIF and video use the immersive capture layout. PNG steps never force movie frames above the requested FPS.
Optional `typingDelayMs` on strict fill/type is planned before the run and applies
between Unicode scalar inputs. The first fill clears once; continuation keeps the
original target and requires focus. Empty paced type performs no input. Privacy,
cancellation and owner checks remain active between characters.
The existing native Stop recording control has an accessible name for assistive
technology and supported AndroidX UI testing. Video acknowledgements retain the
captured document associated with the encoded presentation timestamp, even when
the codec releases an older queued frame after a later snapshot.
The first AVC input waits for bounded codec startup admission instead of silently
dropping the sole frame. Non-budget empty video finalization fails explicitly.
Capture deadlines are measured from the captured origin and gate later actions
and frame admission, including screenshots-only runs; codec finalization does not
extend the exported movie beyond maxDurationMs.
Android OpenAI inference registers each lazy worker before starting transport.
ai-cancel acknowledges the number of requests whose cancellation it requested,
including queued workers. The original ai-infer response reports
INFERENCE_CANCELLED after that worker's provider cleanup has retired; the
cancellation acknowledgement alone is not a terminal inference result.
For supported-interface acceptance without local desktop control, the Android
workflow has an explicit manual native_test input (defaultfalse). It builds matching
debug app/test APKs and CLI, then runs the authored AndroidX Compose/public HTTP
and direct/generic MCP corpus on sequential API35 x86_64 phone/tablet emulators
using hosted KVM. Curated hashes, reports and media are retained for seven days.
Missing KVM is reported as a blocker. These are emulator results, not physical
device or signed-release acceptance. Authenticated host CLI replay now has a separate native-pairing bridge and explicit run/status/download assertions; it must pass before CLI acceptance is claimed.
Strict v1 uses SENSITIVE_CAPTURE_REFUSED, UNRESOLVED_INPUT, DUPLICATE_OUTPUT and
OUTPUT_REDACTION_FAILED consistently with iOS; legacy responses are unchanged.
When a resolved edit target is sensitive, its literal becomes redaction provenance
before capture refusal. Earlier outputs are scrubbed and every capture from that
run is discarded. Any output-redaction failure also discards captures. A separate
discard latch survives later errors, cleanup or Stop; the first concrete failure
and uncertainty flag remain authoritative. Ordinary abort/failure can retain valid
partial captures. Output preparation and capture disposal precede terminal state
and restoration of recording UI.
Native pinch uses the normal WebView built-in zoom mechanism with visible zoom
buttons disabled. Semantic targets still use layout CSS coordinates; native live
and exported pointer/tap overlays map using visual viewport offsets and size from
the same fenced resolver frame. A resize or zoom change invalidates a pending
target before input. Playback's native overlay continues to block ordinary page
touches. G07 hosted tests require pre-play user pinch with measured geometry changes rather than CSS transform simulations. Mid-play pinch/rotation are not presented as a supported shared mobile user route; common stale-token tests remain distinct evidence.
Recording also locks the current native Activity orientation, matching iOS.
Completion, abort, failure and UI disposal restore the exact previous requested
orientation policy. Stop/status remain available while finalization holds the lock.
No orientation setting or new endpoint is exposed.
The native acceptance driver refuses local/self-hosted execution and preexisting
proposed emulator serials/ports. Device commands and cleanup require the spawned
process generation, SDK executable, AVD name and port to match; emulator console
termination additionally checks the actual AVD identity. Seven-day reports retain
failed test counts as well as passes. Original fixture HTTP errors and tiny
negative capture images are retained before assertions; no pairing replies or
credential stores are collected.
Strict v1 script artifact manifests and downloads become available only after
renderer retirement, final output redaction, and capture privacy classification.
Active owned runs return empty artifact lists and ARTIFACT_NOT_READY on valid
chunk requests; unknown or foreign runs return ARTIFACT_NOT_FOUND. Safe terminal
artifacts from earlier runs remain downloadable during a later active run.

Android capture samples the owned window's committed WebView rectangle with
PixelCopy. The native marker is part of that committed scene and is not drawn a
second time. The existing Stop control is in a separate non-focusable window.
Capture checks scene generation, focus, full visibility, geometry, document and
authority around a WebView visual-state and compositor-frame fence. A timed-out
or cancelled PixelCopy cannot publish; its one bounded bitmap
remains quarantined until the native callback recycles it. Subsequent copies
fail closed until that callback retires. Android 10 (API 29) is the minimum
supported OS, providing the frame-commit API used by this path.
A staged tablet viewport temporarily removes its rounded clipping during capture
to provide the complete rectangular WebView scene. Native device replay is pending.

Recording scene certification accounts for the inspector, tab overview, address
editing/menu, open sheets, welcome state, pairing prompt, pending panel requests
and native action modes. Entering or leaving a panel, inspector or action mode
invalidates the scene generation even if it changes back before a copy completes.
The WebView rectangle admits positive, axis-aligned uniform view transforms when
the mapped bounds are pixel-aligned and completely visible; other transforms and
fractional boundaries fail closed to avoid sampling neighboring window pixels.
These checks require native phone/tablet replay before acceptance.