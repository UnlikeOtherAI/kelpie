# Real macOS favourites

The chrome currently renders fixed mock links and reserves 73 points for navigation even when there are no saved bookmarks. Its divider uses a system palette rather than the page-adaptive foreground.

Use the existing BookmarkStore as the sole data source. An empty store removes the 29-point favourites row and its native WebKit underlap; the divider remains at the bottom of the remaining navigation and uses the adaptive foreground at 10% opacity. Saved entries navigate to their stored URLs. Cmd+D, the address star, and More > Add bookmark use one per-window action that rejects start pages, invalid web URLs and duplicates, and reveals the chrome. The native application menu also exposes Add bookmark through the existing active-window command router. Bookmark persistence and APIs remain unchanged apart from injectable defaults for isolated persistence tests.

Verify persistence and duplicate rejection, active-window command routing, conditional underlap geometry, and rendered empty/add/navigate/remove flows. Preserve existing user bookmarks. Run macOS lint/build/tests and CLI checks, release the macOS version, and install the published artifact.

## Cross-Provider Review

Claude CLI review was attempted before implementation but could not authenticate: its OAuth session expired and could not be refreshed. No cross-provider review result is claimed. The implementation retains the existing bookmark store and window command routing rather than introducing a second state owner.

## Tab contrast refinement

The active tab previously mixed 13% white into dark samples, causing the visible mismatch with black page headers. While expanded, let the active tab share the same glass surface as navigation. On collapse, interpolate its opacity to an opaque page-header sample; inactive tabs retain a lighter tint on dark pages. A bounded trailing capture catches delayed sticky-header CSS transitions after scrolling ends. All fills use the existing transition clock.

## Verification

79 macOS tests, Swift lint, Debug and Apple Silicon Release builds, and 541 CLI/shared tests passed. Rendered WebKit checks covered the empty bar, Cmd+D after web-content focus, application-menu and More-menu creation, saved-link navigation, persistence across restart, last-bookmark removal and the 29-point geometry change, plus expanded/collapsed GitHub header contrast. Test-created bookmarks were removed; pre-existing user bookmarks were absent and no user data was cleared. Chromium was not investigated.
