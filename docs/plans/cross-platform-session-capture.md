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
cache paths; the restart check found mixed separators triggering CEF's off-the-record fallback. Linux has no corresponding path change.

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

The user explicitly chose to continue without real Google sign-in. These results
verify native website storage, not a completed Google account authentication or
provider account-chooser reuse.
