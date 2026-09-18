# Windows session and lifecycle completion

This is the implementation review follow-up to the reviewed Windows shipping plan.
It repairs that plan's existing invariants; it does not expand the release scope.

## Defects found at `be8bc35`

- A fresh profile assigns the initial browser `tab-1` and leaves the next allocator
  at 1. The first new tab consequently gets the same ID.
- Restoration changes the active browser pointer but does not show its hidden
  child window or hide the previously visible child.
- Persistence reconstructs the allocator from open tabs. A create/close sequence
  between snapshots loses the retired ID. The engine allocator must be captured.
- `OnBrowserStateChanged` runs after every Win32 message and unconditionally saves
  the session and records history. Idle pumping can rewrite files continuously.
- Session parsing narrows negative JSON integers to unsigned values, accepts the
  maximum next ID without checking increment overflow, and lacks meaningful
  round-trip/retired-ID/selection tests.
- The settings panel reports that a port/profile change will take effect after
  restart, but saves the old values. Home writes happen on an HTTP worker while
  UI settings and shutdown write the same file.
- `CloseTab` removes a browser from the tab collection before `OnBeforeClose`.
  Browser-close cancellation and shutdown must retain the callback owner and
  account for every live CEF browser until its actual close callback.

## Required implementation

Use one engine-owned allocator and tab collection. Capture the next unused ID,
tab URLs/IDs, and active selection together on the engine owner thread. The
Windows persistence layer receives a complete immutable snapshot; it must not
reconstruct allocator state from IDs that happen to remain open.

Emit session changes for successful create, close, selection, and navigation
events from both UI and MCP. Persist only when durable state changes. Suppress
partial writes during restoration and shutdown. The existing CEF navigation
events own history recording; remove the UI pump's duplicate history writes.

Restore validated IDs directly, keep the next unused ID above all allocated IDs,
and show exactly the selected native child window. Fresh profiles start with one
allocated ID and a distinct next ID. Exhausted or corrupt allocator values fail
validation or allocation explicitly instead of wrapping. Navigation generations
and retired IDs must not cause a stale lease to reach a different browser.

Parse JSON defensively with explicit signed/unsigned bounds before conversion.
Reject malformed fields, duplicate/corrupt IDs, overflow, and inconsistent
high-water values without throwing or partially modifying the caller's output.
Define and test handling of invalid entries, multiple active entries, missing
selection, and invalid URLs. Keep parser and tests readable.

Make home/settings writes use the same owner and atomic writer. Persist the
requested supported settings and accurately describe when they apply. Do not
claim a profile migration/restart setting works unless there is an implemented
way for the next launch to discover it; simplify the UI if necessary.

## Verification before commit

- Fresh profile, first new tab, close-last-tab replacement: distinct IDs.
- Several exact restored IDs with a non-first selected tab; visible selection
  agrees with the reported active ID.
- Allocate/close the highest ID before another snapshot; serialize/reload and
  allocate again without reusing it.
- Duplicate URLs remain separate tabs. A closed ID stays absent after restore.
- Negative, zero, fractional, string, oversized, and maximum integers; malformed
  IDs including short strings, trailing garbage, duplicates, and overflow.
- Corrupt snapshots do not throw and do not alter an existing output object.
- No-change events do not write or advance the epoch; changed state does.
- UI and MCP mutations reach the same snapshot path. Background navigation is
  saved without changing active selection.
- Settings/home round-trip, concurrent update ownership, and crash-safe atomic
  replacement are checked independently of a graceful-shutdown save.

Pure model/parser tests can run before live launch is available. The real CEF
restoration and native-window assertions remain required live release gates.
