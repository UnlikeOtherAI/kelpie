# Windows preview review — 2026-09-15

## Scope at the pause

The user requested that new implementation stop after the open edits reach a
buildable checkpoint. The next action is to launch and review the current native
Windows app. This is a preview, not release acceptance or a shipping approval.

Terra owns all implementation. The orchestrator reviews and exercises the build.
The draft shipping PR is [#129](https://github.com/UnlikeOtherAI/kelpie/pull/129).
No release has been published or installed from a published artifact.

## Completed checkpoints

- Protocol/runtime base: local `13c485a`, preserving MCP capability filtering and
  authenticated local CLI attachment.
- Input/cookie planners and production adapters: `147ec93`, `f3c227d`.
  The native Release build and 21 native tests passed at that checkpoint.
- Session/lifecycle changes: `aaf52d8`; CEF Release engine build and session,
  handler, and MCP tests passed. CLI lint/build/test passed: 412 tests, with 63
  live-device tests explicitly skipped without a configured target.
- Native window-control changes: `badeb4e`, after the earlier layout and dispatch
  checkpoints.
- Integrated preview: `cecd3e9819404a3a00346fbab826c18c8ac23dc1`, on
  `codex/windows-qualification-control`, includes the lifecycle checkpoint,
  native controls, tab strip, autocomplete corrections, and packaging changes.
  The fresh DLL linked at 15:49:48 UTC; Release build and 22 native tests passed.
  Original qualification/harness work remains preserved separately on
  `codex/windows-qualification` at `1b02cb4`; it has not all been integrated.

These results are checkpoint-specific. They do not prove real CEF input,
renderer sandbox state, native UI behavior, or Nessie against a running browser.

## Deferred findings from source review

The visible-browser repair below resumes startup, shutdown, and UI work only.
Other findings remain deferred until that review is complete.

1. Domain-only cookie deletion forwards `Network.deleteCookies` without its
   required cookie name. Enumerate and delete exact matching cookies while
   preserving the shared deadline and explicit partial-mutation outcome.
   [Chromium protocol definition](https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/pdl/domains/Network.pdl).
2. Input planning uses DOM UTF-16 selection offsets as UTF-8 byte offsets. This
   breaks expected-state checking when typing around non-ASCII or astral text.
3. Selector-based typing sends End but assumes it appends to the entire value;
   multiline controls need an explicit end-of-content behavior. Interrupted
   multi-event input also needs bounded release of held key/button state.
4. Shutdown still stops and joins HTTP workers before cancelling engine work.
   Returning from `ShutdownDesktopRuntime` on an incomplete close does not, by
   itself, preserve member lifetimes when the containing object is destroyed.
5. Navigation wait state needs further qualification for new-tab/page-driven
   navigation, superseded requests, unavailable back/forward history, and one
   deadline across tab resolution and state probes.
6. Hidden-HWND layout/dispatch failure tests, source responsibility splits and
   size limits, complete version/build metadata alignment, broader authorization
   tests, and the full live acceptance/release gates remain incomplete.

## External blockers at the pause

- GitHub push/network attempts have timed out repeatedly. Some local checkpoints
  are not pushed; the draft PR does not yet contain every completed change.
- npm publishing authentication is unavailable.
- Automatic approval review again rejected the requested preview launch with
  "blocked by policy." The user was asked to open the concrete build manually;
  no alternative launcher was used by the orchestrator.

## Live UI review — failed

The user manually opened the preview executable above. Process 25536 started at
15:55:39 UTC with the default profile. It loaded `kelpie.dll` and `libcef.dll`
from the preview build and owned the listener on `127.0.0.1:8420`.

Native inspection showed a stock menu, square navigation controls and address
field, default bold fonts, and a gray content surface displaying "Chromium
runtime unavailable". The user rejected both the appearance and function.
Ctrl+L left focus on an embedded Chrome address/search control instead of
Kelpie's address field. Several renderer and service subprocesses existed.
The observed executable therefore did not simply lack the CEF DLL.

The fallback STATIC control was hidden in a separate HWND inspection. Its text
remaining visible may be stale painting; this has not been proven. `/health`
responded, `/v1/get-device-info` reported `PLATFORM_NOT_SUPPORTED`, and the token
read from the profile readiness record received 401 from `/v1/get-tabs`. That
record was last written at 15:50:03 UTC, before this process started. The exact
reason it was not replaced remains under diagnosis; no token was logged.

The process and window later disappeared. Neither a crash nor deliberate user
closure has been established. The orchestrator did not close it. No live
navigation, autocomplete, valid screenshot, sandbox, or Nessie acceptance gate
passed during this review.

## Current repair scope

The user's failed-preview report prompted two cohesive Terra repair batches:
browser startup/control recovery, and the existing native UI presentation.
The [visible-browser remediation plan](2026-09-15-windows-visible-browser-remediation.md)
records their scope and live acceptance gates. The user subsequently stopped
Claude use; the prepared review was not submitted, and no Claude work continues.

A separate security-test worktree remains unchanged. Preserve all original task
branches and review documents until their work is accounted for in integration
and release. The local fixture is available at `http://127.0.0.1:60635/` while
its owned Node server remains running. The next concrete build still requires
a real app launch and review; unit tests alone did not detect this failure.
