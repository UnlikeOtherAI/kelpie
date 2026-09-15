# Windows native control completion

Implementation review against runtime `fe77559`. This completes the existing
owner-thread/native-control requirements in the reviewed Windows shipping plan.
The runtime worktree also has uncommitted direct-child resize and visible-child
focus corrections; account for those when consolidating this work.

## Required corrections

1. Keep `NativeWindowControl` and `OwnerTaskQueue` readable. Several complete
   methods are compressed into single lines and cannot be reviewed effectively.
2. Native operations must return success only when the requested Win32 operation
   succeeds. `OwnerTaskQueue` currently catches an exception then reports success;
   fullscreen/resize are void methods that silently ignore Win32 failures.
3. Reset must use the original measured browser content size. The current defaults
   come from outer-window configuration and produce a larger window on reset.
4. `NativeWindowControl::Proc` must pass the received `wparam` to `DefWindowProcW`.
5. Invocation on the owner thread must execute directly. Worker invocation must
   use heap-owned output and abandon pending work before it can execute after a
   timeout. Missing/destroyed dispatcher and post failure must cancel the relevant
   pending task. Shutdown must reject new tasks and release waiting callers.
6. Resizing the viewport must preserve browser chrome position. Adjust the outer
   window for the requested content size, let normal shell layout place the
   browser container, and resize only its direct tab child windows. Never resize
   Chromium's nested internal HWND hierarchy through recursive enumeration.
7. Focus must select the visible native browser child, excluding the hidden
   fallback label and hidden background-tab windows. Restore/switch selection
   must agree with the reported active tab.
8. Native viewport get/reset timeout or failure must not turn into a successful
   empty object through the handler's callback seam. Use an explicit failure
   result, or consistently throw a handled typed exception. Record actual
   resulting dimensions and the supported DPI coordinate convention.
9. After immediate CEF pump work consumes the current deadline, disarm an old
   delayed timer. A timer callback with no pending deadline must stop its timer;
   otherwise idle pumping continues forever. Keep the earliest deadline without
   resetting an already earlier timer on every request.

## Win32 fixture gate

Add a permanent native unit test using hidden test HWNDs only. It must not launch
Kelpie or CEF. Create a top-level window with a toolbar, browser container, direct
tab windows, and one nested child to exercise the real layout and dispatcher.

Verify owner-thread and worker dispatch, timeout before execution, late completion
with owned results, exceptions, shutdown cancellation, and rejected posts. Verify
toolbar/container positions, requested content size, unchanged nested-child size,
default reset, fullscreen style/placement restoration, and visible-child focus.
Pure queue/deadline tests complement this fixture; they do not replace it.

## Build and release alignment

- Windows Release configuration must fail without the pinned sandbox-enabled CEF
  runtime/bootstrap/wrapper and on unsupported architecture, including generator
  paths that do not populate `CMAKE_BUILD_TYPE`.
- Use one component version authority and make RC metadata, runtime device/MCP
  version, packaging, and AGENTS/CLAUDE documentation agree.
- Native UI and sandboxed renderer behavior still require real Kelpie acceptance
  after the launch policy blocker is resolved. Hidden HWND fixture success is not
  evidence of real CEF UI behavior.
