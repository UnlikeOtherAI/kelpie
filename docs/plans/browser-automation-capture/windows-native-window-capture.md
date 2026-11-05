# Owned native-window PrintWindow review plan

This extends only the permanent standard Windows test client. No second interactive task has been registered or run, and the extended C# source has not yet been compiled.

The product remains the exact 9333 candidate. The earlier Session1 Stop test already passed through standard UIA InvokePattern, including partial export integrity, next-run recovery and public cleanup. It was not a physical pointer click.

## Capture scope and implementation

The C# capture mode starts from UIA roots filtered to the exact pinned candidate PID in Session1. It considers only native handles with class Kelpie, KelpieScriptStop or KelpieScriptPresentation. It rechecks each handle's owning PID and visible state before capture. It never traverses or captures another process/window.

PrintWindow with PW_RENDERFULLCONTENT paints into a Graphics.FromImage memory DC. The code does not call GetDC, GetWindowDC, CopyFromScreen, BitBlt, Windows Graphics Capture, SetFocus, SetForegroundWindow, SendInput or any cursor API. It does not add capture borders or a product/debug route.

Each bitmap is at most 4096 pixels per dimension and 8,388,608 pixels; captures are sequential. Every file uses CreateNew and records dimensions, SHA-256, window class/PID, start/end timestamps, PrintWindow return value and bounded pixel diagnostics. Raw captured RGB pixels are saved; there is no exported-renderer fallback or compositing.

Black/blank failure bitmaps are retained as diagnostics. A presentation layer rendered against black without usable transparency is explicitly unsupported. A main window with a black renderer center is explicitly unavailable. An absent UIA-native handle is reported as not exposed. The task must not call any of these a valid After image.

## Proposed one-shot task after root review

- Exact task name: \\KelpieCapture-Windows-UI-Pixels-20261105-9333ff50.
- Same Maxis\\ondre Interactive/Limited principal, no trigger/password, 180-second hard limit.
- Action: existing node.exe and tests/windows/run-interactive-stop-acceptance.mjs.
- Existing candidate and verified CLI entry arguments remain unchanged.
- New test-client binary path: D:/BuildArtifacts/kelpie/capture-windows-20261104/uia-client/printwindow-9333/ScriptStopAutomation.exe.
- Evidence root: D:/BuildArtifacts/kelpie/capture-windows-20261104/uia-native-pixels-9333.
- Private root: D:/Temp/capture-windows-20261104/uia-native-pixels-9333.
- Sixth positional argument: capture.
- New C# compile adds only the installed System.Drawing.dll reference. Preserve the earlier 4ec test client and hash.

The reviewed wrapper still asserts Session1/user, exact EXE/DLL/CLI/UIA hashes and source revision, public alias/readiness/PID/start/launch/listener identity, bounded requests and public teardown. Capture mode creates a temporary button in the owned about:blank tab through the existing authenticated evaluate route, then runs commentary, semantic click and wait. It waits until the click finishes, so the real native marker is present, and captures before the exact owned Stop InvokePattern. No OS input is injected.

Stop and marker capture checks are reported separately. If either is black, unsupported or missing, the capture gate fails while preserving the files and lifecycle result. Native Stop/recovery and normal CLI teardown still run. The exact task is exported and unregistered only after it exits and owned process/socket/readiness/alias cleanup is verified.

## Before/After scope

The Windows recording overlay and Stop state had no equivalent on main 195eb. The Before cell may say that explicitly. Only an actually captured and visually inspected owned native window/popup may be used as After. The existing exported GIF/MP4/PNG evidence remains labelled media and is not a substitute for native-window pixels. Foreground switching/minimize/modal and physical pointer clicking remain separate unverified states.

Capture rechecks GetWindowThreadProcessId and visibility immediately before PrintWindow and again before writing PNG bytes. A mismatch throws while the memory bitmap is disposed, before any image file is created. CLI subprocesses scope USERPROFILE and KELPIE_HOME to the private root; Windows identity/session stay unchanged.
