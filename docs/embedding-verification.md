# Native browser embedding verification

The owning UI lives in the platform browser library. Its home is the complete
browser surface; its doorways are the containing app's chosen native controller,
view, window or scene. Standalone entry points use that same surface.

The host shares its UOA authenticated-request session and account lifecycle
callbacks. Browser tabs, settings, profiles, website data and automation remain
browser-owned. Use one browser session per process and retain it when moving its
presentation between containers.

## Focused checks

Run `pnpm check:embedding` and `pnpm check:macos-signing` at the repository root.
The first checks source ownership; the second checks the direct Mac signing plan
without accessing credentials. CLI source-contract checks use the ordinary
`pnpm lint`, `pnpm build` and `pnpm test` commands.

On Windows, configure `apps/windows` with the matching CEF SDK and wrapper,
`BUILD_TESTING=ON` and `KELPIE_BUILD_EMBEDDING_HOST=ON`. Build, run CTest with
`--no-tests=error`, then launch `kelpie_embed_host.exe`.

On Android, run from `apps/android`:

```sh
./gradlew --max-workers=2 -PkelpieEmbeddingVerificationProfile=true build
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.kelpie.browser.embeddingverify/com.kelpie.browser.EmbeddingHostActivity
```

That debug package uses an embedded storage namespace and never replaces the
standalone package. Open after the Activity has resumed, navigate in two tabs,
move the complete browser, request account sign-in, open settings, close and reopen.
Confirm that the host remains alive and no independent Kelpie login appears.

On Apple platforms, build the existing native-library prerequisites described
in the root README, then generate the app project and build the
`KelpieEmbeddingHost` scheme. Its separate bundle never replaces the standalone
app. The local-only UI test action exercises native Open, Move and Close controls,
two navigated tabs and the host UOA callback. Use the same renderer flag when
generating different Apple projects in one checkout.

For Mac Store inputs, generate with
`TUIST_KELPIE_WEBKIT_ONLY=true tuist generate --no-open`. Run the ordinary Kelpie
unit scheme through its hollow native test host. Check resource loading,
host-session fencing, browser-owned website storage, unavailable renderer rejection
and the embedded-window authority tests. For direct distribution, generate without
the flag and verify Chromium in addition to WebKit.

Check a standalone Mac background launch with `--port` on a free port and
`GET /health`. The service must start before a browser window appears. Optional
Mac menu commands must follow the browser when its controller moves windows.

On Linux, build `apps/linux` and run its native tests. The app consumes
`core/native` and keeps its own UI. A build without CEF proves source/dependency
wiring; it does not prove Chromium packaging or a GTK browsing journey.

## Evidence and limits

The extraction was exercised on 8 November 2026:

| Environment | Revision exercised | Result |
| --- | --- | --- |
| Maxis, Windows CEF | `0ba03f38` | Build and 56 native tests passed. |
| Minis, Windows native host | `0ba03f38` | Two saved tabs retained their page across window moves; sign-in delegated to the host; browser close left the host running. Initial tab creation/navigation also passed at `b799295a`. |
| Maxis signing, Minis signed Windows package | Native build `0ba03f38`, packager `752cfd0d` | The exact signed ZIP passed publisher, timestamp, profile EKU and matching CEF certificate checks. Native launch, new tab, address-bar navigation and normal close passed. Incorrect input hash was rejected before signing. |
| Maxis, Android | `875b44f3`, then `fd361de1` | Full debug/release build, lint and 158 unit tests passed; version 0.2.0 build passed. |
| Minis, API 35 tablet emulator, WebView 124 | `875b44f3`, then `fd361de1` | Late creation, two navigated tabs, reparenting, delegated sign-in, settings, close and reopen passed. The final 0.2.0 APK retained both pages across moves and close/reopen. |
| dictator, iPad simulator | `17a1f494`, then `962ee0de` | Native embedding UI journey passed; final source build and focused account/resource tests passed. |
| dictator, Mac WebKit | `962ee0de` | 226 native unit tests passed, including background-launch parsing and host-window authority checks. |
| dictator, Mac embedded WebKit host | `8a27c940`, then `f0298f5e` | AppReveal native controls verified tabs, host sign-in, window moves, detach and reattach. Final source opened a second tab and navigated to IANA. |
| dictator, Mac Chromium embedded host | `f0298f5e` | Native address-bar navigation, delegated sign-in, window moves, detach and reattach passed with the page retained. Real Chromium helper processes and the packaged resource bundle loaded. |
| dictator, Mac static-link and tracking-area checks | `f0298f5e` | Both focused native regressions passed through the supported `xctest` interface after `build-for-testing`. SwiftLint passed with no violations. |
| dictator, signed standalone Mac | `962ee0de`, then `f0298f5e` | Background launch answered health on the requested port 18434. Final candidate passed deep signature verification, timestamp/hardened-runtime checks, notarization, stapling and Gatekeeper assessment. |
| Fedora 44 on Maxis, GTK/native build without CEF | `1db43445` | Build, 36 native tests and the supported executable help interface passed. |

Mac XCTest UI automation timed out enabling automation mode on this machine.
The Mac native controls above were exercised through AppReveal, with native
Accessibility keyboard input for the SwiftUI address field; a successful
XCTest UI run is not claimed. The iPad XCTest UI journey did pass. A full direct-CEF Mac unit run through
`xcodebuild test` did not report test startup on this Mac; the two new regressions
passed through direct `xctest`, and the earlier WebKit-only 226-test run passed.

Physical phones and an iPad external monitor were not exercised. The iOS
presentation API accepts a host-selected `UIWindowScene`; that API and container
reparenting do not establish external-monitor hardware acceptance. Store signing,
sandbox installation and Store review are separate checks. Production Nessie
window entry points and its UOA adapter are not included in this extraction.

## Apple consumer modules

The browser library imports the existing C ABI through `KelpieNative` and the
direct Mac renderer through `KelpieChromium`. These are implementation-only imports: the public Swift module exposes no C ABI
or renderer types. Consumers import the built `KelpieBrowser` module. The
browser library does not use a Swift bridging header: its module must remain
importable by an unrelated containing target. The hollow app test targets retain
their own test-only headers. WebKit-only consumers never import the Chromium
module. Native archives and the resource bundle are still required at link and
package time; importing the Swift module alone does not establish packaging.

Build a containing-app SDK with `bash scripts/build-apple-sdk.sh macosx arm64
/absolute/new/output` (or iphoneos/iphonesimulator and the supported architecture).
It builds the six C++ libraries and pinned llama runtime, compiles the complete
WebKit browser, combines the static archives, stages its public Swift module and
resource bundle, and checks an unrelated import from the staged framework. The
macOS package retains Metal inference; iOS uses the portable native runtime.
The containing app links the static framework with C++, AppIntents, Accelerate
and, on Mac, Metal, and copies KelpieBrowserResources.bundle into the bundle that
contains the linked browser code. These SDK outputs contain no executable app,
CEF engine or helper, signing identity, host credential or standalone launcher.

Apple sessions expose terminal `close()` for host retirement. It detaches the
outbound agent connection and input monitor, stops local listeners, aborts script
playback, invalidates browser references, flushes traffic and closes owned tabs
and windows. A closed session cannot create a new surface; create a new session
for a new runtime. Moving a controller between containers retains its session.
This teardown API alone does not select a different person's local browser profile.

Before opening a signed-in Apple browser, call
`try await KelpieBrowserProfile.activate(issuer:subject:)` from the host's current
UOA grant. Close the previous runtime and retire its provider before changing
people. A profile owns its preference suite, files, secrets, website data store,
history, bookmarks, inference configuration and partition mappings. Retained
writers keep the original store; old routers refuse work after a profile change.
The same issuer/subject preserves that person's data across proof or team changes.
Concurrent runtimes and profile transitions are refused. The Mac profile API
requires the WebKit-only consumer build; CEF's process data directory cannot be
replaced after bootstrap. Standalone browser storage remains unchanged.

The supported direct macOS library test interface is
`bash scripts/test-macos-library.sh /absolute/KelpieTests.xctest
KelpieTests.HostSessionTests,KelpieTests.BrowserProfileTests`. Run it in the
logged-in GUI session when WebKit needs WindowServer. The launcher validates
the bundle and selectors and supplies an explicit environment allowlist; developer
credentials never enter the XCTest process or its failure diagnostics. Confirm
the expected test count, rather than accepting an empty selector run.
The allowlist also supplies the containing test host's adjacent MacOS directory
for Xcode Debug dylib loading; it never inherits a developer DYLD search path.

## Android containing builds and profiles

The Android library can be consumed as an isolated Gradle included build at
core/android (com.unlikeotherai.kelpie:browser:0.2.0). Its Kotlin and Compose
compiler versions remain scoped to that build. The consumer build uses AGP 8.12
and requires Gradle 8.13 or newer; Android variant matching requires the host
to use that same AGP version. A host can use a newer Kotlin
compiler without replacing the browser compiler or duplicating its UI.

For a signed-in embedded browser, verify the bearer owner with UOA before calling
KelpieEnvironment.configureProfile(issuer, subject). Call it before the first
browser/environment initialization in that process. Browser files, preferences
and the default WebView profile are scoped to that person. The process cannot
switch an initialized browser profile: close it and start a new browser process
for another person. A signed-out host uses a separate signed-out profile.
The containing app must require Android 28 and MULTI_PROFILE support for this
capability; it must not fall back to the containing app’s cookie jar.

Native Windows/Curl host providers can reuse AccountTransport for the fixed
embedded profile, avatar, browser bookmark and connection endpoints. Other
embedded routes and query-bearing paths are refused. The containing app still
owns the grant and verifies its returned UOA subject before selecting a profile;
this transport does not create a standalone sign-in or refresh session.

The native JSON dependency remains v3.11.3. Its source archive is fetched from
the official codeload tag URL with SHA-256
0d8ef5af7f9794e3263480193c491549b2ba6cc74bb018906202ada498a79406.
This replaces a release-asset URL that returned repeated HTTP 504 on both build
hosts; it does not select another JSON version or add a network fallback.

Windows hosts can observe BrowserSession::IsClosing() before IsClosed(). Retire
the host session provider as soon as closing begins, while continuing the normal
message pump and Tick until IsClosed(). This unblocks pending account/renewal
work before the SDK waits for its shutdown barrier and preserves the containing
app’s lifetime.
