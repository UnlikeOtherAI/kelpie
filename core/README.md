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
`apple/Project.swift` and import `KelpieBrowser`. Create a `KelpieBrowserSession`
with the host's `KelpieUOASession`; use `KelpieBrowserView` or a native controller.
Keep the session (and the Mac `KelpieBrowserSurface`) alive while changing containers.
The browser resource bundle is a library dependency. Chromium hosts also package
the matching signed CEF framework and helper; the library does not install it.

Android hosts include the Gradle library at `core/android`, create
`KelpieBrowserSession(activity, uoaSession = ...)` before the activity starts, and
attach its view to their container. `KelpieBrowserActivity` is an optional full-window
host. The application initializes `KelpieEnvironment` without subclassing its app.

Windows hosts link `Kelpie::Browser` from `core/windows` and include
`kelpie/browser.h`. Set `AppConfig.hosted`, `parent_window` and `uoa_session`, then
call `Start`. Forward browser messages through `ProcessMessage`, call `Tick` from
the host loop, and drain `RequestClose` before destruction. A hosted browser never
posts `WM_QUIT` to the containing app. CEF's bootstrap sandbox contract still applies.

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
