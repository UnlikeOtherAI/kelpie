# Floating Menu Dynamic Radius

## Problem

The floating action menu no longer spaces its buttons correctly once more actions are added.

- On macOS, the new 3D inspector action caused fan buttons to overlap because the fan still uses a fixed angle sequence that does not scale with the current item count.
- On iOS and Android, the fan already distributes actions across a semicircle, but the radius stays fixed even as the action count grows, so adjacent buttons can eventually collide.

The fix must land on macOS, iOS, and Android so future floating-menu buttons do not require manual per-platform retuning.

## Root Cause

- macOS uses a hard-coded angular step and half-arc instead of deriving the fan geometry from the actual number of visible buttons.
- iOS and Android derive the angles from the item count, but they still use a hard-coded spread radius.
- None of the three platforms enforces a direct spacing invariant such as "adjacent action centers must stay at least one button width plus gap apart."

## Plan

1. Keep the current half-circle fan behavior and screen-edge clamping; do not introduce a new menu shape.
2. Replace fixed fan constants with a shared geometric rule per platform:
   adjacent buttons on the fan must remain at least `menuItemSize + minimumGap` apart along the arc.
3. Derive the minimum radius from the current item count using the semicircle step angle and chord length, then clamp upward from the existing base radius so current spacing does not regress for smaller menus.
4. Apply the same count-based radius calculation on macOS, iOS, and Android, while preserving each platform's existing action order and extra UI such as the tablet viewport picker anchor.
5. Update the floating-menu docs to state that the fan radius grows automatically as more actions are present.

## Cross-Provider Review

External Claude review agreed with the direction but called out two risks:

- a half-circle fan still has a scaling ceiling, so a much larger future action count may eventually require a different layout instead of unbounded radius growth,
- and the spacing formula only applies to the current uniform circular icon buttons, not to mixed-size controls.

Assessment:

- Keep the half-circle fan for now. The current menu is still in the single-digit action range, so adding a second layout mode now would be premature.
- Scope the radius rule to the existing circular action buttons only. The tablet preset pills already sit outside the fan and do not use this geometry.
