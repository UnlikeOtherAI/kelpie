# Shared Viewport Presets in UI and MCP

**Goal:** Use one named viewport preset catalog across iPad tablets, Android tablets, and macOS, and expose those presets through the browser HTTP/MCP surface so LLMs can inspect and activate them directly.

**Recommendation:** Add explicit preset APIs instead of overloading raw `resize-viewport` semantics. Keep raw resize for arbitrary dimensions, and add named preset methods for the shared device categories. Linux should report that named viewport presets are not supported yet.

---

## Requirements

- iPad tablets and Android tablets must keep using the shared device-category presets in the floating menu.
- macOS must use the same named preset catalog instead of the older ad hoc `iPhone/Tablet/Laptop/Custom` set.
- The browser HTTP API and browser MCP must expose the named presets so an LLM can:
  - list available presets for the current device/window geometry
  - activate one of those presets
  - observe which preset is currently active
- Raw `resize-viewport` and `reset-viewport` must keep working.
- Linux must explicitly remain unsupported for named viewport presets for now.

---

## Shared Preset Catalog

Use these shared preset IDs and labels on every supported platform:

- `compact-base` -> `Compact / Base`
- `standard-pro` -> `Standard / Pro`
- `large-plus` -> `Large / Plus`
- `ultra-pro-max` -> `Ultra / Pro Max`
- `book-fold-internal` -> `Book Fold (Internal)`
- `book-fold-cover` -> `Book Fold (Cover)`
- `flip-fold-internal` -> `Flip Fold (Internal)`
- `flip-fold-cover` -> `Flip Fold (Cover)`
- `tri-fold-internal` -> `Tri-Fold (Internal)`

Each preset should also carry:

- display inches label
- pixel resolution label
- representative portrait viewport size used for staging

The UI may keep shorter pill labels where needed, but the API and MCP should return the full category names.

### Canonical preset table

This rollout will use one dedicated catalog file per target instead of repeating inline arrays inside views/handlers:

- iOS: one `ViewportPresetCatalog` source file
- Android: one `ViewportPresetCatalog` source file/object
- macOS: one `ViewportPresetCatalog` source file
- CLI/MCP docs: one shared TypeScript definition for tool schemas/examples

Cross-language import is not practical in the current repo layout, so the invariant is: one catalog definition per target, zero view-local duplicates, and all implementations must match the exact table below.

| ID | API Label | Inches | Pixels | Representative Portrait Viewport |
|---|---|---|---|---|
| `compact-base` | `Compact / Base` | `6.1" - 6.3"` | `1170 x 2532 - 1206 x 2622` | `393 x 852` |
| `standard-pro` | `Standard / Pro` | `6.2" - 6.4"` | `1080 x 2340 - 1280 x 2856` | `402 x 874` |
| `large-plus` | `Large / Plus` | `6.5" - 6.7"` | `1260 x 2736 - 1440 x 3120` | `430 x 932` |
| `ultra-pro-max` | `Ultra / Pro Max` | `6.8" - 6.9"` | `1320 x 2868 - 1440 x 3120` | `440 x 956` |
| `book-fold-internal` | `Book Fold (Internal)` | `7.6" - 8.0"` | `2076 x 2152 - 2160 x 2440` | `904 x 1136` |
| `book-fold-cover` | `Book Fold (Cover)` | `6.3" - 6.5"` | `1080 x 2364 - 1116 x 2484` | `360 x 800` |
| `flip-fold-internal` | `Flip Fold (Internal)` | `6.7" - 6.9"` | `1080 x 2640 - 1200 x 2844` | `412 x 914` |
| `flip-fold-cover` | `Flip Fold (Cover)` | `3.4" - 4.1"` | `720 x 748 - 1056 x 1066` | `360 x 380` |
| `tri-fold-internal` | `Tri-Fold (Internal)` | `~10.0"` | `2800 x 3200` | `980 x 1120` |

---

## API Shape

Add two new browser methods:

### `get-viewport-presets`

Returns:

- `presets`: all shared presets with metadata
- `availablePresetIds`: presets that fit the current device/window geometry
- `activePresetId`: current active named preset or `null`
- `supportsViewportPresets`: boolean

### `set-viewport-preset`

Request:

```json
{
  "presetId": "compact-base"
}
```

Response:

- selected preset metadata
- resulting live viewport size

If the preset does not fit or is unknown, return `INVALID_PARAM`.

Keep `reset-viewport` as the way to leave named preset mode and return to the platform default/full viewport.

### MCP names

- `kelpie_get_viewport_presets`
- `kelpie_set_viewport_preset`

### State rules

- A preset is considered available when its oriented viewport size is less than or equal to the current available stage size on that platform.
- `resize-viewport` always clears `activePresetId` and enters raw custom viewport mode.
- `reset-viewport` always clears `activePresetId` and exits raw custom viewport mode, returning to the platform default/full viewport.
- `set-viewport-preset` returns:
  - `INVALID_PARAM` when `presetId` is unknown
  - `INVALID_PARAM` with `reason: "unavailable"` when the preset is valid but does not fit current geometry

---

## Platform Behavior

### iPad and Android tablets

- Named presets are a shell-stage feature backed by the real live web view frame.
- The browser view should keep publishing the list of presets that fit the current geometry.
- MCP/API preset changes must update the same shared selection state the floating menu uses.
- If geometry changes and the active preset no longer fits, clear it instead of keeping a stale hidden selection.

### macOS

- Replace the old local preset enum with the shared preset catalog plus:
  - `full` shell mode
  - `custom` for arbitrary `resize-viewport`
- The top bar should switch from the old icon-only segmented preset control to a compact popup/menu control that can fit the longer shared category names.
- Named presets should stage the viewport in the existing centered shell.
- `reset-viewport` should leave preset/custom mode and return to full shell viewport.
- If the macOS window is resized smaller and the active preset no longer fits the current stage, clear `activePresetId` just like tablets do.

### Linux

- Do not add support now.
- `get-viewport-presets` and `set-viewport-preset` should return `PLATFORM_NOT_SUPPORTED` on Linux once a Linux browser surface exists.
- Documentation must say Linux does not support named viewport presets yet.

---

## Files

- `apps/ios/Kelpie/Views/BrowserView.swift`
- `apps/ios/Kelpie/Views/FloatingMenuView.swift`
- `apps/ios/Kelpie/Handlers/DeviceHandler.swift`
- `apps/ios/Kelpie/Handlers/BrowserManagementHandler.swift`
- `apps/android/app/src/main/java/com/kelpie/browser/ui/BrowserScreen.kt`
- `apps/android/app/src/main/java/com/kelpie/browser/ui/FloatingMenu.kt`
- `apps/android/app/src/main/java/com/kelpie/browser/handlers/DeviceHandler.kt`
- `apps/android/app/src/main/java/com/kelpie/browser/handlers/BrowserManagementHandler.kt`
- `apps/macos/Kelpie/Browser/ViewportState.swift`
- `apps/macos/Kelpie/Views/URLBarView.swift`
- `apps/macos/Kelpie/Handlers/DeviceHandler.swift`
- `apps/macos/Kelpie/Handlers/BrowserManagementHandler.swift`
- `packages/cli/src/mcp/tools.ts`
- `docs/api/README.md`
- `docs/api/core.md`
- `docs/api/browser.md`
- `docs/functionality.md`
- `docs/ui/mobile.md`

---

## Risks

- If tablets keep preset selection only in local composable/view state, MCP-triggered preset changes will not update the UI.
  - Mitigation: move selection and available-preset IDs into a small shared store per platform.
- If macOS keeps the old segmented strip, the shared preset list will not fit and the control will degrade badly.
  - Mitigation: switch macOS preset selection to a popup/menu control.
- If `reset-viewport` keeps old macOS behavior, named presets will behave differently across platforms.
  - Mitigation: redefine macOS reset to return to the full shell viewport.

---

## Cross-Provider Review

Claude review accepted the overall shape with required clarifications:

- Specify one fit predicate across platforms: a preset is available only when its oriented width and height are each less than or equal to the current available stage size.
- State that `resize-viewport` always clears `activePresetId`.
- State that `reset-viewport` always clears `activePresetId` and returns to the full/default viewport on every platform.
- Extend the stale-selection clearing rule to macOS window resizes, not just tablets.
- Name the new MCP tools explicitly.
- Include the exact preset pixel table in the design so parity-critical values are not left implicit.

Reviewer verdict: conditional accept after those clarifications.
