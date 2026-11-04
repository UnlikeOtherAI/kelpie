# Shared login sessions and responsive capture on mobile

## Defects and scope

Mac PR #176 fixed full-history serialization on every captured request. iOS and
Android still perform the same full native export, decode and preferences rewrite
for each request. Windows/Linux CEF append directly to the native store and do
not have that capture hot path.

The four login surfaces already use the same default website store/request
context as ordinary browser tabs. Native UOA sign-out clears the app's account
session, not Google's browser cookies. We must preserve that distinction.

Mobile `new-tab` currently ignores `partition` and `persistent`, silently sharing
cookies even when isolation was requested. Session snapshots contain only URLs,
so adding isolated views without changing restoration would also leak them into
the default profile on restart. Android cookie endpoints always use the global
CookieManager and must instead use the target WebView's profile.

## Implementation

- Reuse the Mac incremental network mirror and coalescing private atomic file
  persistence on iOS through source references; retain iOS deselection behavior.
  Android gets the same bounded writer design with immutable entry snapshots,
  one pending write, retry, legacy migration only after successful file write,
  and flush when the activity backgrounds. Capture never serializes old bodies.
- Ordinary tabs and account login remain on the default persistent profile.
  Provider popups stay in their opener's profile. No cookie copying between
  isolated and default stores, no new identity server records or login UI.
- Implement the existing named, persistent partition contract on both mobile
  apps: iOS 17+ named WKWebsiteDataStore identifiers; Android MULTI_PROFILE with
  WebViewCompat.setProfile before any WebView configuration or navigation.
  Unsupported runtimes return PARTITION_UNSUPPORTED before creating a tab.
- Mobile `persistent:false` is rejected explicitly on both platforms. Android's
  supported WebView profile API cannot promise memory-only storage; a disk
  profile deleted later is not an implementation of that promise. This keeps
  mobile behavior aligned without weakening the existing protocol guarantee.
- Validate names with the shared partition rules, return actual partition/name
  metadata in tab responses, scope cookie operations to the target view, and
  persist typed session records. Legacy URL-only snapshots migrate as default
  tabs. Invalid or missing isolated mappings are skipped, never made default.
- Listing and deletion use registry mappings. Deletion first closes its tabs and
  retires the mapping. Android cannot delete a profile loaded in this process;
  record a durable pending deletion and report PARTITION_IN_USE when the engine
  refuses. Retry pending deletion before any profile loads on the next launch.
  Reusing a retired partition name creates a fresh profile, never the old one.
- Expose mobile partition tools in the shared CLI and native MCP catalogues.
  The deletion validator accepts engine-reported orphan IDs without allowing
  those IDs to create tabs.
- Keep Windows/Linux source unchanged unless runtime verification exposes a
  defect. Exercise their existing default/global CEF and explicit contexts.

## Verification

Focused tests cover capture append/eviction/selection parity, file migration,
coalescing and restart, partition validation/restoration and profile routing.
Native WebKit/WebView tests use real cookies (including HttpOnly), localStorage,
ordinary siblings, a named sibling and a different named partition. Exercise
login and ordinary-tab entry points, cancellation/reopening, restart and named
partition deletion. Actual Google account chooser/session reuse is reported
separately from synthetic cookie evidence; missing credentials are not a pass.

Use the released iPhone simulator only while the favorites chat owns the Mac
app, Android emulators and Maxis build capacity. Linux checks run in Fedora only
as bounded platform verification. Do not erase shared app data to recover tests.

## Cross-Provider Review

Claude reviewed this design read-only before implementation. Accepted: generation
UUIDs for Android profiles and pending-purge records, durable UUID maps, deletion
races, startup cleanup before login or tab views, active-index recovery, storage
API audit, backup/file protection, and bounded background flush. Coalescing is a
full rewrite of at most the native store's 2,000 retained entries once per second;
it snapshots entry references, not body bytes. Startup migration is one-time.

Retained the existing PARTITION_IN_USE protocol for a failed physical purge,
with durable pending identifiers visible to listing/retry; a new success shape
or new persistence error code is unnecessary. Mobile persistent:false was never
implemented, so rejecting it removes false success, not working isolation.

Did not introduce a new Swift package solely to move two already shared source
files. Network inspection remains an app-wide developer log, as on desktop;
partition isolation concerns website identity/storage and does not promise to
hide requests from the app's inspector. Login surfaces have no capture bridge.
No new redaction policy or partition-tagged network schema is introduced here.

Release requires iOS/Android and CLI/shared version bumps, docs, focused/native/manual checks,
one merged PR and published/installed artifacts. Windows 0.1.15 also normalizes the profile directory before deriving any CEF
cache paths; the restart check found mixed separators triggering CEF's off-the-record fallback. Linux 0.1.14 shares the desktop restoration guard: all named contexts must
be ready before any restored page opens. A failed context stops initialization
without reopening its URL in the shared profile or overwriting the saved tabs.

## Runtime verification

On 4 November 2026, iOS 26.5 on the existing iPhone 16 Pro Max and iPad Air
simulators passed real WebKit HttpOnly cookie and localStorage checks through
the paired HTTP interface. Ordinary siblings share identity; named siblings
share only their named identity; another partition starts empty. Popup navigation
keeps the opener's identity. Restart preserved both default and named stores.
The native login sheet opened, cancelled back to the tab, and reopened.

The deletion check exposed WebKit retaining a retired renderer briefly after
SwiftUI removed its tab. A bounded 300 ms retry, matching Mac behavior, lets
normal teardown finish. The final iPhone check deleted isolated tabs, preserved
the ordinary session, and recreated the same public partition name with empty
storage. Seventeen focused iOS tests also passed after integrating PR #177.

Fedora 44 exercised the published `release/2026-10-11.3` RPM in its desktop
session with the published CEF configuration. Shared/isolated HttpOnly cookies,
localStorage, popup inheritance and persistence across restart passed.
Windows 11 on Maxis passed the same sharing/isolation fixture using installed
Kelpie 0.1.11. The extracted published 0.1.12 artifact on D: hit CEF network-service
crashes and blank pages; that artifact's session behavior is not verified.
The 0.1.11 restart check also exposed lost isolated localStorage with a
forward-slash profile argument. CEF logged that it could not create the
profile. Its ChromeBrowserContext compares the profile parent directly with
the normalized user-data directory and silently creates an off-the-record
profile on mismatch. Normalize the absolute Windows profile path before
deriving the shared and named cache paths; do not change or copy cookie stores.

Android API 35 on Maxis (WebView 124.0.6367.219) passed the production
TabStore/cookie-handler instrumentation: shared and named HttpOnly cookies,
localStorage boundaries, profile mapping restoration, retirement and empty
identity after reuse. A fresh MainActivity launch purged all three pending
profiles. The full Gradle build, unit tests and ktlint passed.

The final Linux source build passed all 35 native tests on Fedora 44. Native
HTTP checks passed shared/named cookies and localStorage, popup inheritance,
restart and deletion. The failure fixture covered an unavailable isolated
store both first and later in the saved tabs: startup loaded no pages, kept
the session intact, and recovered after removal of the injected fault.

Portable checks on Maxis passed lint, build, 629 CLI tests (one skipped), the
shared tests and three focused native MCP/gateway tests.

Windows 0.1.15, built from `975655fd` on Maxis, passed 53 native tests over SSH;
the visibility test passed in the interactive desktop session (54 total).
The signed installed build passed the storage fixture, popup inheritance,
restart, partition deletion and empty identity after reuse. The test used the
normal Windows user profile and a forward-slash profile argument. Existing
tabs and storage were preserved. The separate D: test profile hit renderer and
tab-operation timeouts while the drive's average disk queue reached 95;
those failed runs and debugger traces remain separate from the passing run.
Remote desktop UI inspection required an unavailable VNC password, so this
Windows evidence is from the real native browser's supported HTTP interface.

The executable, client DLL and adjacent `chrome_elf.dll` were signed on Minis
using the existing Azure Artifact Signing profile. All three passed Authenticode,
publisher-specific EKU, timestamp and SignTool checks with the same certificate,
as required by the pinned CEF bootstrap. The interactive signing session worked;
SSH could not access the existing Azure broker credential.

Android's account control opened the secure login activity, cancelled back to
the original page, and reopened successfully through the mirrored native UI.
The activity's existing `FLAG_SECURE` prevents inspection of the login content
through that mirror; it was left enabled.

The additional live Android HTTP check exposed a legacy dispatch defect:
`BrowserGatewayBinding.legacy` acquired the browser lease but invoked handlers
on the server coroutine. Canonical dispatch already enters the main thread.
Legacy dispatch now enters that same main-thread boundary before creating a
WebView or accessing its profile. A native regression calls the router from
`Dispatchers.Default` and creates and inspects a real partitioned WebView.
Legacy dispatch also resolves its selected renderer from TabStore before
running a handler. Compose updates its visible-view binding later; using that
binding could otherwise read the previous tab's profile immediately after a
switch. The regression deliberately leaves that visible binding stale.

The final Android build passed 158 unit tests and ktlint on Maxis, plus both
instrumented storage/dispatch tests on emulator-5554. The paired HTTP fixture
passed default/named HttpOnly cookies, JavaScript invisibility, localStorage,
restart, retirement and empty identity after reusing a name. A native keyboard
activation opened the popup in its existing isolated view and kept its cookie.
The mirror's mouse input delivered pointer-down and pointer-up at different
positions, so that input failure was not treated as an app popup failure.
Android also requires a user gesture for popups by default, as documented in
[WebSettings](https://developer.android.com/reference/android/webkit/WebSettings#setJavaScriptCanOpenWindowsAutomatically(boolean));
the fixture supports `--android --manual-popup` for this native flow.
After cleanup, the original tab remained and the next startup automatically
purged all five retired fixture stores. The persistence ordering test's latch
wait is 30 seconds: slow temporary-file creation on D: exceeded its previous
five-second coordination timeout; its ordering and final-content assertions
remain intact.

The user explicitly chose to continue without real Google sign-in. These results
verify native website storage, not a completed Google account authentication or
provider account-chooser reuse.

## Installed-release follow-up

The 0.1.20 iPhone restart check exposed another legacy dispatch race: TabStore
had selected the next tab, but SwiftUI had not rebound HandlerContext.webView.
Navigation reached the preceding view. iOS now snapshots the active WebView at
legacy dispatch using a task-local value keyed to the HandlerContext instance.
Suspension and UI rebinding cannot change that request's renderer; another
context, canonical dispatch and pinned account jobs retain their own authority.
Missing active tabs fail explicitly. Android already uses the equivalent
coroutine-local target under its gateway lease. iOS advances to 0.1.21.
An unavailable page during restoration also made WebKit reset its URL to nil;
the tab observer then overwrote its saved destination with an empty string.
The observer now retains the destination until WebKit supplies a replacement.
New tabs record their requested URL before loading, and a real failed provisional
navigation regression checks that an offline isolated tab keeps its identity.

The Ubuntu 22.04 release container's default GCC 11 cannot compile the existing
C++20 atomic shared pointer in desktop connection code. Its build now selects
the official Jammy GCC 12 package, retaining the Ubuntu 22.04 runtime baseline.
The Debian package declares libstdc++6 >= 12. Linux advances to 0.1.15 because
its build inputs changed; connection concurrency code stays unchanged.

### Cross-provider review of the follow-up

A read-only Claude review identified mutable-context races, main-actor access,
missing active tabs, pinned/external contexts and the GCC runtime floor. The
implementation adopts a request-local renderer instead of mutating the visible
binding. Router.handle and its dispatch helper are MainActor-isolated. Cookie
handlers capture the selected WebView and use its own websiteDataStore, with no
separate shared cookie store. Tests cover stale UI binding, suspension, a second
context, missing selection, canonical dispatch and pinned/external contexts.
The compiler variables stay in the container shell running CMake, and Debian
metadata includes the newer libstdc++ dependency. Installed checks and release
results must be recorded separately from compilation.

At revision b76a66c2, the iPhone 16 Pro Max simulator (iOS 26.5) passed the
ordinary/named/other-store checks, HttpOnly visibility, localStorage and a native
popup tap. Two consecutive restarts with the fixture server unavailable retained
the tabs; bringing the server back and immediately switching/navigating each tab
preserved all storage boundaries. Eight focused storage tests passed, including
the unavailable-page regression, with no compiler warnings. Strict SwiftLint
passed. The Ubuntu 22.04 container compiled and ran an atomic shared-pointer
probe with stock g++-12/libstdc++6 12.3; the complete release build is separate.
The downloaded signed Android 0.1.19 APK passed the same live storage, popup,
restart and deletion checks on Maxis's API 35 emulator, including automatic
purging of retired profiles after restart. Existing tabs were preserved.
