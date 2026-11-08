# Embeddable Kelpie browser

The core contains the complete browser: native tabs, address bar, menus, settings,
rendering, profiles, automation, MCP and Nessie connectivity. Standalone apps in
`apps/` supply entry points, branding, permissions, signing and packaging.

- `native/`: the existing shared C++ libraries, Chromium engine and desktop account/connect services.
- `apple/shared/`: shared Apple behavior, account integration and browser resources.
- `apple/macos/` and `apple/ios/`: native browser components and presentation APIs.
- `android/`: the Android browser library, including its native UI and JNI bindings.
- `windows/`: the complete Windows browser library and host-window integration.

The Linux app keeps its own shell and consumes `core/native`; it has no dependency
on the Apple, Android or Windows browser components.

## Host boundary

A containing app shares its UOA session through an authenticated-request provider.
It owns sign-in, refresh, revocation and durable credential storage. Kelpie must not
copy its refresh token or create a second sign-in. Identity and session changes
fence outstanding browser work. Standalone hosts use the core's existing UOA login.
Browser state, tabs and UI belong to Kelpie, independently of the host's interface.

Apple hosts link the `KelpieBrowserMac` or `KelpieBrowserIOS` target in
`apple/Project.swift` and import `KelpieBrowser`. Apply the matching
`KelpieBrowserBuild.mac(core:)` or `.ios(core:)` link settings from
`Tuist/ProjectDescriptionHelpers`; these include the native libraries for the
consumer and test targets. Create a `KelpieBrowserSession`
with the host's `KelpieUOASession`; use `KelpieBrowserView` or a native controller.
Keep the session (and the Mac `KelpieBrowserSurface`) alive while changing containers.
The browser resource bundle is a library dependency and owns the artwork, font,
diagnostics and inspector scripts. Hosts keep only their launch icons. The Mac test scheme loads CEF from the packaged standalone fixture without launching
its browser or account lifecycle. Chromium hosts also package
the matching signed CEF framework and helper; the library does not install it.

Android hosts include the Gradle library at `core/android`, create
`KelpieBrowserSession(activity, uoaSession = ...)` when needed, and
attach its view to their container. `KelpieBrowserActivity` is an optional full-window
host. The application initializes `KelpieEnvironment` without subclassing its app.
The session carries its own view lifecycle owners, supports creation after activity
startup, and releases its composition and callbacks on close. The standalone
package registers its OAuth callback; embedded hosts delegate sign-in to their UOA session.

For the debug-only Android host, build with `-PkelpieEmbeddingVerificationProfile=true`
and launch `com.kelpie.browser.embeddingverify/com.kelpie.browser.EmbeddingHostActivity`.
Open the browser after startup, move its view between containers, and close it
without closing the host. This fixture is absent from release packages.

Windows hosts link `Kelpie::Browser` from `core/windows` and include
`kelpie/browser.h`. Set `AppConfig.hosted`, `parent_window` and `uoa_session`, then
call `Start`. Forward browser messages through `ProcessMessage`, call `Tick` from
the host loop, and drain `RequestClose` before destruction. A hosted browser never
posts `WM_QUIT` to the containing app. CEF's bootstrap sandbox contract still applies.

Windows Chromium hosts enter through `BootstrapBrowserHost`, preserving CEF's
subprocess dispatch, SDK version and sandbox checks. Call
`kelpie_stage_browser_runtime(target)` to stage the matching runtime and, for a
DLL consumer, its bootstrap launcher. The core never stages a standalone app
launcher on its own. Embedded views leave resize, caption buttons and window
movement to the host. Automation that needs to resize or fullscreen an owned
window refuses to change a containing app window.

The opt-in Windows fixture is built with `-DKELPIE_BUILD_EMBEDDING_HOST=ON` in
`apps/windows`. Run `kelpie_embed_host.exe`: create tabs and navigate, move the
complete browser between windows, request sign-in, and close only the browser.
Its signed-out UOA provider reports account callbacks in the host; it stores no
credentials and is excluded from ordinary release builds.

Apple unit tests use a hollow test app to provide the native application lifecycle
required by persistent WebKit profiles. It never starts the standalone browser,
restores its UOA credentials or binds its local control service.

## Verification and delivery

This extraction is under implementation. Native compilation, installed flows,
external-display behavior, Store compatibility and Nessie host integration must be
recorded before claiming delivery. Source relocation alone is not release evidence.

Embedded Mac views draw their own tabs without changing the host window chrome.
Only input inside the browser pauses its agent work. KelpieBrowserPresentation on
iOS moves one complete browser controller between a parent and a host-selected
UIWindowScene, including an iPad external display, without replacing its tabs.

Embedded preferences, files and WebView profiles are separate from the host.
Standalone profile locations remain unchanged. Embedded website storage is persistent
on iOS 17+, macOS and current Android WebView providers. iOS 16 embedded browsing uses
an isolated in-memory website store; websiteDataIsPersistent reports that limit.
Android embedding requires the existing multiple-profile WebView capability.
It keeps the containing app's process-wide WebView debugging policy intact.

## Apple Store build

Generate with `TUIST_KELPIE_WEBKIT_ONLY=true tuist generate` for a sandboxed macOS
consumer. The same browser UI, tabs, settings and automation compile against
WebKit. Chromium code, helper executables and framework packaging are omitted;
the renderer API rejects unavailable engines. Generate without that variable for
the existing direct-distribution Chromium build. iOS always uses WebKit.

This selects build inputs and entitlements; Store signing, review and installed
sandbox verification remain separate release checks. No Store approval is implied.
