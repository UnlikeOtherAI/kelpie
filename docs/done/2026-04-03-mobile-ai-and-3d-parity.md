# Mobile AI And 3D Parity

## Problem

iPad is missing two browser-shell features that already exist on desktop or in the documented mobile design:

- there is no visible AI entry point in the iOS browser UI,
- and the 3D inspector is not wired into the iOS or Android browser shells at all.

The project parity rule means iOS and Android need the same user-facing behavior in the same change.

## Root Cause

- iOS never added the mobile AI UI described in the local-inference plan: no URL-bar brain button, no floating-menu brain button, and no AI sheet/screen.
- Android is in the same state for AI shell UI.
- 3D inspector routing, bridge state, and floating-menu buttons were only implemented on macOS.
- the current 3D bridge interaction model is desktop-only: mouse drag, wheel zoom, and keyboard shortcuts.

## Plan

1. Add a minimal mobile AI surface on both iOS and Android:
   a visible brain button in the URL bar,
   a matching brain action in the floating menu,
   and a simple native AI status sheet that is explicitly read-only and only reports backend/model/capability state so the feature is discoverable immediately.
2. Add mobile 3D inspector support on both iOS and Android:
   the same `snapshot-3d-enter`, `snapshot-3d-exit`, and `snapshot-3d-status` routes used on macOS,
   browser-shell toggle action,
   and floating-menu entry point.
3. Reuse the existing 3D DOM transform engine. Add only the minimum touch affordances needed on mobile:
   one-finger drag to rotate plus on-screen zoom/reset buttons. Do not add hover replacement, pinch gestures, or a separate mobile-specific 3D mode.
4. Extend programmatic panel routing so AI can be opened the same way as bookmarks/history/network/settings.
5. Update functionality and mobile UI docs last, after the final UI shape is in place.

## Cross-Provider Review

External Claude review flagged four real risks:

- touch-first 3D controls can easily expand beyond parity work,
- the AI surface needed a precise scope definition,
- the mobile 3D API routes had to be explicitly called out,
- and docs should follow implementation rather than sit beside it as a peer step.

Assessment:

- Keep the AI scope narrow: read-only status sheet only.
- Keep the 3D scope narrow too, but not zero-touch. A direct port without basic rotation/zoom affordances would be unusable on iPad and Android tablets, so minimal touch drag plus on-screen zoom/reset stays in scope.
- Reuse the existing macOS route names for mobile so the HTTP/API contract remains aligned.
