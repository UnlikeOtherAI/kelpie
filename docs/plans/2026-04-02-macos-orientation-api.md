# macOS Orientation API Clarification

## Problem

On macOS, external automation can hit a dead end when trying to change viewport orientation:

- `set-orientation` currently returns `PLATFORM_NOT_SUPPORTED`, which is misleading.
- In reality, orientation is meaningful only when a named staged viewport preset is active.
- `full` mode has no independent orientation.
- `custom` mode currently ignores orientation changes entirely.

That makes MCP/HTTP callers guess why the action failed.

## Change

Implement macOS `set-orientation` against `ViewportState`, but only for preset mode.

- If a named preset is active: change orientation and return the new viewport.
- If mode is `full`: return a structured error explaining that orientation cannot be changed until a smaller viewport preset is selected.
- If mode is `custom`: return a structured error explaining that raw custom sizes do not support orientation changes and the caller should either resize explicitly or switch to a named preset.

Also tighten the mac toolbar so the portrait/landscape control is enabled only in preset mode, matching the actual behavior.

## Why This Fix

This fixes the broken invariant directly:

- The API now describes the real capability boundary instead of pretending macOS has no orientation support.
- The UI no longer advertises a control state that does nothing in custom mode.

No new endpoint is added. Existing endpoint semantics become accurate.

## Verification

- `set-orientation` in `full` mode returns an explanatory error.
- `set-orientation` in `custom` mode returns an explanatory error.
- `set-orientation` in preset mode changes the viewport dimensions.
- Toolbar orientation control is disabled in `full` and `custom`, enabled in preset mode.

## Cross-Provider Review

External Codex review findings:

- Fixing only `set-orientation` is incomplete because macOS `get-orientation` currently lies with a hard-coded `landscape` value while `get-viewport` already reports the real derived orientation.
- Shared MCP metadata already treats `kelpie_set_orientation` and `kelpie_get_orientation` as available on macOS, but the native MCP registry still marks them mobile-only. Leaving that mismatch would keep HTTP, CLI, and native MCP inconsistent.
- The minimum-complexity fix is still the proposed one, but it must include `get-orientation` correctness and MCP registry alignment, not just the explanatory `set-orientation` error.
