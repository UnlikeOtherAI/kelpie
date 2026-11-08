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
| Maxis, Android | `875b44f3` | Full debug/release build, lint and 158 unit tests passed. |
| Minis, API 35 tablet emulator, WebView 124 | `875b44f3` | Late creation, two navigated tabs, reparenting, delegated sign-in, settings, close and reopen passed. |
| dictator, iPad simulator | `17a1f494`, then `962ee0de` | Native embedding UI journey passed; final source build and focused account/resource tests passed. |
| dictator, Mac WebKit | `962ee0de` | Native unit suite passed, including background-launch parsing and host-window authority checks. |
| dictator, Mac embedded host | `8a27c940` | AppReveal native controls verified tabs, host sign-in, window moves, detach and reattach. |
| dictator, signed standalone Mac | `962ee0de` | Background launch answered health on the requested port 18434. |
| Fedora 44 on Maxis, GTK/native build without CEF | `1db43445` | Build, 36 native tests and the supported executable help interface passed. |

Mac XCTest UI automation timed out enabling automation mode on this machine.
The Mac native controls above were exercised through AppReveal; a successful
XCTest UI run is not claimed. The iPad XCTest UI journey did pass.

Physical phones and an iPad external monitor were not exercised. The iOS
presentation API accepts a host-selected `UIWindowScene`; that API and container
reparenting do not establish external-monitor hardware acceptance. Store signing,
sandbox installation and Store review are separate checks. Production Nessie
window entry points and its UOA adapter are not included in this extraction.
