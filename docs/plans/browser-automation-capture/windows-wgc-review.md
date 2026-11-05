# Review plan: exact owned-HWND Windows Graphics Capture

This is an API/SDK assessment and plan only. No WGC capture implementation, item, session or task has been created or run.

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

Capture one item at a time with a fixed two-frame pool, at most 4096 pixels per dimension and 8,388,608 pixels. Wait at most 5 seconds for one frame; use a bounded staging texture and original frame ContentSize/row pitch. Reject size changes. No unbounded frame queue or retained history. The task remains within the existing 120-second run plus 30-second public-cleanup budget and 180-second hard limit.

Save the actual native frame without adding markers, merging another source, changing RGB/alpha heuristically or substituting exported renderer pixels. Record raw alpha statistics; preserve native transparency only if the API actually supplies it. A black/blank/unsupported frame fails. Any permission/picker requirement or access denial stops the test without interaction or an alternative capture source.

A callback completion fence cancels late writes after timeout. Before creating any PNG, recheck current ownership and cancellation. The output is a fresh owned file and records method, native handle/class/PID/start, bounds, timestamps and SHA-256. After one frame, revoke the callback and close frame/session/pool/item/D3D resources. No WGC item survives task completion.

## Spatial marker evidence

Before any new positive pixel claim, query the owned synthetic button rectangle and actual CSS viewport/DPR/visual scale through the existing authenticated page API. Record the trusted click geometry. Project that expected center/radius into the exact captured presentation-window coordinates.

Require a connected red component inside that expected region, with center/extent/area consistent with the configured radius. ClearType text fringes, native chrome red pixels, a Stop-only image and an unsupported black/transparency bitmap must all fail. Keep negative fixture regressions for the real PrintWindow false positive.

The current test gate fails closed unless this explicit spatial/radius component evidence exists. The WGC implementation and pixel validator need root source review and a separate run authorization. A normal capture border must disappear with the owned session; do not request borderless access.
