# Android browser chrome and mobile account parity

## Problem and scope

Android still exposes a floating fan menu and bottom tab pills. iOS already has
native bottom navigation, top tablet tabs, and phone tab previews. Bring Android
to that mobile design while retaining every existing inspector, automation,
pairing, recording, and viewport action. The desktop screenshot supplies the
neutral title strip, curved tab shoulders, page-colour selection and hairline;
phones retain their mobile bottom toolbar rather than desktop window controls.

## Implementation

1. Replace Android's floating fan with a labelled More menu in a 62 dp bottom
   toolbar, collapsing to a 34 dp domain surface. Navigation controls have 44 dp
   targets. Keep history completion, reload/stop, keyboard insets and accessibility.
   Move auxiliary actions to More at narrow widths. Expand on tab change and
   address editing; scroll uses accumulated directional movement, ignores bottom
   overscroll, and reveals at the top.
2. Tablets have a persistent 48 dp neutral grey tab strip, including one tab.
   Put New tab at the left on both mobile platforms. Every tab can close,
   including the final tab (the store creates a fresh replacement). Only the
   selected tab gets page colour. Sample the visible WebView top edge into a tiny
   bitmap after navigation and scrolling, never a persistent page script. Animate
   colour and draw the inverse foreground separator at 10% opacity. Inactive
   tabs and the strip remain neutral, regardless of page colour.
3. Add a two-column Android overview matching iOS, accessible through More and
   an upward address drag. In-memory thumbnails are captured before overview;
   restored tabs show a placeholder until viewed. Close buttons and horizontal
   card dismissal work independently from selection. Closing selected tabs uses
   the existing store; do not create another tab model.
4. Split BrowserScreen along viewport and menu responsibilities before extending.
   Preserve recording's chrome-free surface and all HTTP/MCP handlers.
5. Add native public OAuth to Android and iOS after the chrome pass. Signed-out
   account action opens hosted Login/register immediately, external browser first.
   Android's no-browser fallback is an isolated activity/process with a separate
   WebView data directory and no automation bridge or tab registry. Use random
   state, S256 PKCE and an exact app callback; keep tokens in memory, cancel and
   expire cleanly. Reuse Foundation account/transport/bookmark logic for iOS via
   platform guards and ASWebAuthenticationSession. No client secret, config
   signing key, domain bearer, native password form, or credential logging.
6. Cloud favourites are a separate account-scoped in-memory view. Local favourites
   remain untouched. Reuse the server's ETag compare-and-swap contract; merge
   explicit queued mutations into the newest snapshot, preserving opaque fields.
   Logout invalidates outstanding generations before restoring local data.
   Implement account UI and sync on iOS in the same commit as Android.
7. Branding/social providers remain selected by server-managed verified config.
   The intended existing config is not yet identified. Do not add an arbitrary
   client-supplied domain selector or weaken confidential /auth/token handling.

## Verification and delivery

- Ubuntu owns Android builds. Provision JDK 17 and pinned SDK/NDK dependencies,
  run Gradle build (including ktlint and unit tests), then phone/tablet emulator
  interaction and screenshots. Verify tab lifetime, narrow widths, input focus,
  slow scrolling, colours, More actions, persistence and HTTP/MCP reachability.
- Unit-test scroll thresholds and palette contrast; account tests cover PKCE/state,
  cancellation, expiry, stale callbacks and concurrent favourites edits.
- Mac owns iOS simulator/device builds and Swift lint. Run existing chrome tests
  plus shared account tests. Check equivalent phone/tablet UI and safe areas.
- Update functionality/mobile docs, bump affected mobile versions, publish Android
  APK/AAB and iOS artefacts as supported by signing, install the published Android
  artefact and verify. Report actual host/device checks and any signing constraints.

## Cross-Provider Review

Completed before implementation; dispositions follow.

### Review disposition (Claude, 2026-09-25)

Accepted: separate chrome delivery from account integration; split BrowserScreen
first; match iOS user-drag-only scroll thresholds; debounce active-only sampling
with generation checks; cap previews at 12; include explicit iOS left-plus parity.
Use PixelCopy of the visible top strip so hardware WebViews are sampled correctly.
Account implementation will use a dedicated callback Activity, application-owned
state, explicit cancellation on process loss, and a platform-specific presentation
adapter around shared Foundation services. Never persist tokens/profile/avatar.
Foreign bookmark metadata and the existing desktop automation contract must be
covered by tests. Paired browser automation already controls favourites; mobile
will follow that explicit existing contract rather than invent a second store API.

Not accepted as blockers: the user explicitly requires hosted fallback when no
browser exists; it remains isolated and will not bypass provider restrictions.
PKCE protects intercepted authorization codes for a public native client; a
verified App Link requires operator domain deployment and is not manufactured by
this app change. Config selection cannot be trusted to client_name. The secure
server profile remains a separate dependency, and no client secret is introduced.


### Implementation security review

A second Claude review identified per-mutation error attribution, bookmark date
interoperability, launcher ownership during rotation, denied callback handling,
and fallback cancellation. These are fixed in the account implementation. Apple
uses one shared coordinator and platform presentation adapter. Android's launcher
lives in MainActivity with a weak current host; pending login survives Activity
recreation, and an application-private cancellation broadcast closes the isolated
fallback. Each login registers a fresh public client rather than persisting an
unverifiable stale registration. Auth state never becomes a normal browser tab.

Shared Apple favourites now retain raw entries during mutation, accept fractional
ISO dates and keep one UI item per stable identifier. Malformed foreign entries
remain opaque instead of being discarded when adding a different favourite.
The existing paired-browser automation contract is retained; no new protocol
scope field or unsolicited extra permission step is introduced.

### Android screen-change lifecycle correction

Tablet-to-phone verification exposed an existing service race: MainActivity's
onDestroy queues stopService and clears a global stage, then the replacement
Activity stages a new server. KelpieNetworkService.onDestroy reads that mutable
global instead of its own server, leaking the old listener. Repeated configuration
changes can also stop a newly requested foreground service before promotion.

The service retains the exact stage it started and stops that stage on replacement
or destruction. MainActivity handles screen, density, orientation and keyboard
configuration changes itself, as a WebView host;
Compose still receives configuration updates. This preserves tabs and account
presentation across resize and avoids unnecessary foreground-service restarts.
Verify repeated phone/tablet switches, one live listener, unchanged process,
session restoration and hosted-login cancellation. No HTTP protocol change.

Claude's adversarial review caught the remaining asynchronous teardown race.
Accepted: the Activity synchronously stops its own stage before recreation, clears
only that stage by identity, and leaves the foreground service alive during
configuration changes. The service retains and stops its exact stage rather than
reading mutable global state in onDestroy. This makes actual ownership explicit.
The optional configuration declaration is separate, for preserving browser tabs;
it is not relied upon to fix service teardown. Verify with resize and rotation
plus unhandled configuration recreation. Shutdown already ran on the main thread;
this correction does not add a new blocking operation.

## Verification results

- Ubuntu: Gradle build and bundleRelease pass, including ktlint, Android lint,
  all four native architectures, and 23 JVM tests in each build variant.
- Android API 34: phone/tablet layouts, page-edge dark-to-light tab colours,
  static inactive strip, collapsed toolbar, tab overview, new tab and horizontal
  dismissal verified in the emulator displayed on the Linux VNC desktop.
- The development-signed release APK is not debuggable. Default-browser login
  and no-browser hosted fallback both launch. On the production `user` image,
  the fallback process has no DevTools socket; Back returns to Kelpie. WebView 113
  deliberately ignores disable-inspection requests on userdebug/eng systems;
  this was reproduced and checked against Chromium's SharedStatics source.
- Six phone/tablet transitions and two unhandled night-mode Activity recreations
  retain the process, recover HTTP readiness, and leave exactly one listener on
  8420, with no fatal exception or occupied-port error. Public device info reports
  Android 0.1.4 and requires pairing.
- Mac: strict Swift lint, arm64 Release build, deep codesign verification and four
  shared account tests pass. iOS: eight shared/chrome tests and browser UI tests
  on iPhone 17 Pro and iPad Pro 11-inch pass.
- No live user credentials were entered. Branding, social-provider configuration
  and successful user sign-in still require the intended server profile. The APK
  uses a development signing certificate; the AAB is unsigned and the iOS zip is
  a simulator build, not a physical-device IPA or store submission.
