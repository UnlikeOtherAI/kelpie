# iPad Mobile Stage Plan

**Goal:** Improve the tablet browser shells so the welcome card does not sprawl wider than a standard modal, and add a tablet-only phone viewport picker that stages the browser inside a phone-sized frame.

**Recommendation:** Keep this as an iPad shell feature, not a fake browser-management API implementation. The toggle should change the actual `WKWebView` frame in the UI so viewport reads naturally reflect the staged size.

---

## Requirements

- On iPad, the welcome card should cap its width to roughly the same width as a modal/form sheet instead of stretching across the screen.
- On tablets, the phone viewport control should live in the floating menu, not the top bar.
- When enabled, the web content should render inside a centered phone-sized stage, similar to the macOS staged viewport.
- The staged size must honor the tablet orientation:
  - portrait tablet -> phone portrait viewport
  - landscape tablet -> phone landscape viewport
- On iPhone, nothing about the shell should change.

---

## Design

### Welcome card

- Add an iPad-aware max width to the welcome overlay card.
- Use a conservative modal-like cap instead of a percentage-based width so the card stays readable and visually consistent.

### Tablet mobile stage

- Add a tablet-only phone icon in the floating menu.
- Tapping that icon should open pills offset from the icon itself instead of immediately toggling the stage.
- Persist the selected preset in `AppStorage` / shared preferences so it survives relaunches.
- Mirror the same behavior on Android tablets.
- When enabled on tablets:
  - wrap the browser content area in a stage
  - center the `WKWebView`
  - size the viewport to a selected shared device-category preset
  - choose portrait vs landscape phone dimensions based on the live available content orientation
- Only show preset pills that fit the current tablet geometry.
- Use the shared category list:
  - `Base`, `Pro`, `Plus`, `Max`
  - `Book`, `Book C`
  - `Flip`, `Flip C`
  - `Tri`
- Increase the floating-menu fan radius and use a true half-circle spread so seven icons fit without crowding.
- When disabled, keep the existing full-width browser behavior.

### Why not use the existing viewport HTTP endpoints?

- The current iOS viewport endpoints are mostly response stubs and do not drive real UI layout.
- Patching those endpoints first would increase scope and still not solve the user-visible shell problem directly.
- A shell-stage approach is simpler and fixes the real invariant: the browser should actually become smaller on iPad when mobile mode is enabled.

---

## Files

- `apps/ios/Kelpie/Views/BrowserView.swift`
- `apps/ios/Kelpie/Views/FloatingMenuView.swift`
- `apps/ios/Kelpie/Views/WelcomeCardView.swift`
- `apps/android/app/src/main/java/com/kelpie/browser/ui/BrowserScreen.kt`
- `apps/android/app/src/main/java/com/kelpie/browser/ui/FloatingMenu.kt`
- `docs/functionality.md`
- `docs/ui/mobile.md`

---

## Risks

- If the stage dimensions are persisted from raw device orientation instead of actual content geometry, split-view or unusual size classes could choose the wrong preset.
  - Mitigation: derive portrait vs landscape from the content area geometry, not `UIDevice.current.orientation`.
- If the staged viewport is implemented as a visual scale effect instead of a real frame change, `get-viewport` and interaction coordinates will become misleading.
  - Mitigation: constrain the actual web view container frame.

---

## Cross-Provider Review

Attempted via local Claude CLI, but the installed CLI is not logged in on this machine (`Not logged in · Please run /login`), so a true cross-provider review could not be completed from the current environment.

Local review accepted:

- Keep the iPad mobile mode as a shell-stage feature, not a fake implementation of the existing viewport HTTP stubs.
- Derive portrait vs landscape from the live content geometry instead of `UIDevice.current.orientation` so split-view and other constrained layouts do not pick the wrong preset.
- Constrain the actual `WKWebView` frame so viewport reads and interaction coordinates stay truthful.
- Move the tablet-only phone control into the floating menu on both iOS and Android so the top bar stays clean on large screens.
- Expand the floating-menu arc and radius instead of shrinking icons or tightening hit targets.
- Use shared device-category pills rather than a boolean toggle so the staged viewport matches an explicit simulated device class.
