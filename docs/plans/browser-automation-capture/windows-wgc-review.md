# Review plan: exact owned-HWND Windows Graphics Capture

Test-only source is implemented for review. The helper and C# clients are now compiled; only synthetic validator fixtures have run. No WGC item, session or task has been created. Capture requires separate reviewed-run authorization.

## Read-only findings

Maxis runs OS build 26300. Its installed 10.0.26100.0 SDK includes windows.graphics.capture.interop.h, C++/WinRT Graphics.Capture and Direct3D11 projections, CreateFreeThreaded, IncludeSecondaryWindows and D3D11/DXGI/windowsapp/WIC libraries. WinRT metadata confirms GraphicsCaptureSession is present. Session1 runtime support/privacy permission remains untested.

[Microsoft CreateForWindow](https://learn.microsoft.com/en-us/windows/win32/api/windows.graphics.capture.interop/nf-windows-graphics-capture-interop-igraphicscaptureiteminterop-createforwindow) targets a single HWND without a picker and is available from Windows 10 version 1903. [Microsoft's Win32 sample](https://github.com/microsoft/Windows.UI.Composition-Win32-Samples/blob/master/cpp/ScreenCaptureforHWND/ScreenCaptureforHWND/capture.interop.h) uses this interop path. [Borderless capture](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession.isborderrequired?view=winrt-22621) requires a consent request; this plan makes no such request and retains the normal border. [Secondary windows](https://github.com/MicrosoftDocs/winrt-api/blob/docs/windows.graphics.capture/graphicscapturesession_includesecondarywindows.md) default to excluded and will stay excluded.

The earlier PrintWindow main image contained no marker; global red counts came from ClearType fringes. Stop pixels were valid. The presentation-window bitmap had unsupported black/transparency content. Raw results and independent failed review remain preserved; no renderer fallback or product rendering change is proposed.

## Proposed test-only helper

- A small C++/WinRT executable under tests/windows, built against the installed SDK only. No product launcher, service, app dependency or shipping source change.
- Same reviewed on-demand Interactive/Limited task and public CLI/private profile lifecycle, with a fresh exact task name and evidence/private roots after source review.
- Explicit WGC mode rather than silently falling back from PrintWindow.
- First verify Session1, GraphicsCaptureSession.IsSupported and exact candidate EXE/DLL/PID/start time/launch/socket identity.
- Resolve only an exact own-process native presentation HWND from the standard scoped UIA client. Recheck HWND class, PID and process-start identity before CreateForWindow, after frame acquisition and immediately before persistence.
- Create no monitor/desktop capture item. IncludeSecondaryWindows stays false; a second popup, if needed, gets a separate exact own-HWND item.
- No picker, RequestAccessAsync, borderless permission, focus, cursor movement, SendInput, screen DC or desktop capture. Cursor inclusion may be disabled for this session only; that does not move/hide the real cursor.
- Keep the normal OS capture border. It is not the prohibited Computer Use helper border. Close the capture session/pool/item and helper process on every path; verify task teardown destroys all owned capture resources.

## Bounds and failure rules

Capture one item at a time with a fixed two-frame pool, at most 4096 pixels per dimension and 8,388,608 pixels. Wait at most 5 seconds for one frame; deep-copy the frame into a bounded SoftwareBitmap and validate ContentSize/row pitch. Reject size changes. No unbounded frame queue or retained history. The task remains within the existing 120-second run plus 30-second public-cleanup budget and 180-second hard limit.

Save the actual native frame without adding markers, merging another source, changing RGB/alpha heuristically or substituting exported renderer pixels. Record raw alpha statistics; preserve native transparency only if the API actually supplies it. A black/blank/unsupported frame fails. Any permission/picker requirement or access denial stops the test without interaction or an alternative capture source.

A callback completion fence cancels late writes after timeout. Before creating any PNG, recheck current ownership and cancellation. The output is a fresh owned file and records method, native handle/class/PID/start, bounds, timestamps and SHA-256. After one frame, revoke the callback and close frame/session/pool/item/D3D resources. No WGC item survives task completion.

## Spatial marker evidence

Before any new positive pixel claim, query the owned synthetic button rectangle and actual CSS viewport/DPR/visual scale through the existing authenticated page API. Record the trusted click geometry. Project that expected center/radius into the exact captured presentation-window coordinates.

Require a connected red component inside that expected region, with center/extent/area consistent with the configured radius. ClearType text fringes, native chrome red pixels, a Stop-only image and an unsupported black/transparency bitmap must all fail. Keep negative fixture regressions for the real PrintWindow false positive.

The current test gate fails closed unless this explicit spatial/radius component evidence exists. The WGC implementation and pixel validator need root source review and a separate run authorization. A normal capture border must disappear with the owned session; do not request borderless access.

## Implemented review boundary

Explicit mode wgc requires absolute helper and validator paths. ScriptStopAutomation supplies exact owned HWND descriptors and captures the Stop window separately. wgc_owned_window.cpp captures only KelpieScriptPresentation. wgc_capture_files.h writes exclusive owned files. NativeMarkerValidator.cs independently checks raw/PNG hashes and every alpha byte, then requires a connected component at the API-observed click center and configured radius. Synthetic fixtures reject wrong-center and ClearType-like fringes. WIC uses standard premultiplied-to-straight PNG conversion; raw BGRA and the API alpha mode remain unchanged. No background is synthesized.

Proposed fresh task: KelpieCapture-Windows-WGC-20261105-f188883f, no triggers, InteractiveToken/Limited, Maxis user ondre. Evidence root: D:/BuildArtifacts/kelpie/capture-windows-20261104/uia-wgc-f188. Private root: D:/Temp/capture-windows-20261104/uia-wgc-f188. Both roots and task name must be absent and port28420 free. Freeze the test revision, compiled paths and hashes before registration. Use public CLI candidate f188 with explicit wgc mode and a trusted immutable build-identity manifest. Export only the owned definition/result; close through public CLI, verify process/socket/readiness cleanup, and unregister only the matching task. Preserve52960 and other owners.

Build requires VS C++20, SDK26100 C++/WinRT, existing nlohmann headers and the owned-file helper. Link d3d11, dxgi, windowsapp, windowscodecs, bcrypt, ole32 and user32. Compile one helper with /W4 /WX /MT; no app/CEF/llama rebuild. Compile C# clients with /warn:4 /warnaserror+ and UIAutomation/System.Drawing references as applicable. C++ /W4 /WX /MT compilation and C# /warn:4 /warnaserror+ compilation passed. Independent synthetic validator fixtures passed3/3. Initial SDK TimeSpan conversion, missing user32 link and C# local-variable scope failures are preserved in ignored wgc-e83-review, review2 and review3 logs. Runtime support and native marker pixels remain unclaimed.

## Final-candidate pinning and compiled review evidence

WGC mode requires an absolute immutable JSON manifest as its final argument. Its exact keys are source (40 lowercase hex), exeSha256, dllSha256 and cliSha256 (64 lowercase hex). It is loaded before launch; report records its SHA256, validates all binaries, and derives a source-scoped alias. No authored HTTP/body field selects trusted identity. Earlier9333 reports remain historical. The new native candidate is f188883fbbbf16703b3154d81ed609d187a4e4fa, EXE54c8be31e003853947182c9461755bf4e7be5f91a2c64fcfb97ed5da1a32d755, DLL421e4162fca5ab484ce2901b087800e435e9272a48fd6e161d9cffc5f9fdf60f.

Compiled helpers: D:/BuildArtifacts/kelpie/capture-windows-20261104/wgc-e83-review3. WGC executable SHA0e989c8944b391eab88a980be046bfa636a54bfa9a8f34adf33c411f6eb7a3ee; UIA SHA c3c6da4306fcf618b4deca2550a215ff24042e966162c3e7dcee2d793a14d034; validator SHA0245ab3b5b76bcc780a208a000abf87e30b0b09d493f990702e45197a6a6cf31. Complete source/binary hashes are in privacy-f188-evidence/final-hashes.json. All compilation used one logical CPU/Normal priority; free memory12.68..15.72GiB. No capture item/session/task was executed by these checks.

## Preserved first final-candidate attempt

The one granted Session1 task ran with the exact manifest/helper hashes, but failed before scene preparation completed and before WGC was invoked. Raw report: D:/BuildArtifacts/kelpie/capture-windows-20261104/uia-wgc-f188/report.json. The task result is1; candidate40652/Session1 was closed through the public CLI. The exact definition was verified before unregistering; process/socket/readiness/alias/task absence and preserved52960 are recorded in uia-wgc-f188-task-cleanup.json. No WGC output directory exists and no native marker screenshot is claimed.

A permanent fixture API probe now records about:blank secure-context/crypto availability, the legacy preparation primitive/expression outcome, and a preparation variant with a Node-generated synthetic document identity. The latter has two passing no-page-crypto/injection regression tests. Concrete native cause and this probe runtime outcome are pending the next resource slot; the UI action still uses its old setup until diagnosis confirms the fix.

## Confirmed fixture cause and reviewed retry source

The supported f188 API probe native-fixture-f188/fixture.json confirmed about:blank isSecureContext=false and crypto.randomUUID undefined; both the legacy primitive and full preparation expression returned JAVASCRIPT_ERROR. The Node-generated UUID preparation succeeded at target230,180, viewport1042x662/DPR1. The UI action now consumes that tested shared fixture function and records explicit phase/error-code diagnostics. Two fixture VM regressions pass; these supplement the actual native probe rather than establish its result.

The first diagnostic flow itself returned failure because its immediate post-stop check observed the still-exiting original process. Raw report is preserved. The common owned-exit wait now validates PID/path/start identity, waits at most5seconds without terminating anything, and rechecks the exact original. Its PowerShell transport is bounded at10seconds including startup. The Job parent remains alive through this wait; Job close is not used as evidence of supported shutdown. Runtime wait verification is pending the next short probe.

A reviewed retry uses fresh task KelpieCapture-Windows-WGC-20261105-f188883f-attempt2 and fresh evidence/private roots uia-wgc-f188-attempt2. Native source, build manifest and the three compiled helper hashes stay unchanged. The same hard Job mask1/Normal/2GiB/no-breakaway policy applies,170second Job and180second Task cap. Action work remains bounded120seconds; public abort/pending/stop plus exact-exit verification has a40second worst-case cleanup budget, within the unchanged whole-task cap. No WGC retry occurs before root reviews this source.
