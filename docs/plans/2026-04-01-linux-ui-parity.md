# Linux UI Parity Plan

**Goal:** Make the Linux shell visually align with the macOS shell instead of using generic GTK defaults.

## Root Cause

The Linux GUI currently exposes working browser functionality, but the shell widgets are still stock GTK:

- text-only navigation buttons instead of icon chrome
- no shared toolbar palette or rounded control groups
- no Font Awesome brand icons for renderer affordances
- a generic `Menu` button instead of the orange floating action button used on macOS

That creates a visual mismatch even when browser behavior is correct.

## Simplification First

The right fix is a small Linux UI theme layer, not ad hoc per-widget styling.

Linux should:

- reuse the same visual tokens already established by macOS
- load the existing Font Awesome Brands font from the repo for brand icons
- style GTK widgets through a shared CSS provider and small helper functions
- keep functional behavior in existing widgets while upgrading presentation

## Visual Source Of Truth

From the macOS app:

- FAB color: warm peach/orange `rgb(244,176,120)`
- menu item color: deeper orange `rgb(240,148,90)`
- toolbar groups: neutral control background with subtle outline
- renderer group: Safari and Chrome brand icons
- floating menu actions: reload, Safari auth, bookmarks, history, network, settings

## Proposed Linux Changes

1. Add a Linux UI theme helper for:
   - color constants
   - CSS provider registration
   - Font Awesome font registration
   - helper creation of icon labels/buttons
2. Upgrade the URL bar to:
   - icon-only back/forward/reload buttons
   - rounded URL entry styling
   - a renderer pill group using Font Awesome Chrome/Safari icons
3. Replace the generic menu button with:
   - a circular orange floating action button
   - icon-bearing popup items using the macOS action set/order
4. Stage the shared Font Awesome OTF into the Linux build output so the running binary can load it consistently.

## Cross-Provider Review

Attempted with the local `claude` CLI before implementation, but the machine was not authenticated (`Not logged in · Please run /login`), so no external review response was available for this change.
