# iPad View Menu Viewport Presets

## Goal

Expose the currently available staged phone viewport presets in the iPad `View` menu.

## Root Cause

The iPad app already reads the canonical phone viewport preset catalog from `core/native/core-protocol` and exposes it through the floating menu and HTTP/MCP APIs, but the iPad scene commands only contain the app-menu help items. There is no `View` menu integration for staged viewport selection.

## Plan

1. Keep the C++ viewport preset catalog as the source of truth.
2. Reuse the existing Swift preset reader and the persisted `available preset ids` state from `BrowserView`.
3. Add an iOS notification channel for `select viewport preset`.
4. Add an iPad-only `View` command menu with:
   - `Full Width`
   - one item per currently available phone preset
5. Route those menu actions back into `BrowserView`, which already owns the live preset selection state.
6. Update user-facing docs to mention the iPad `View` menu.

## Constraints

- Do not introduce another preset catalog in Swift.
- Do not bypass `BrowserView` state ownership.
- Only show presets that currently fit the device geometry.

## Cross-Provider Review

Pending.
