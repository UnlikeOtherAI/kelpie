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
