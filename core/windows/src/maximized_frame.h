#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows {

// The edges of one monitor that hold an auto-hiding taskbar or other appbar.
struct AutoHideEdges {
  bool left = false;
  bool top = false;
  bool right = false;
  bool bottom = false;
};

// How much of an auto-hide appbar's edge a maximized window leaves uncovered.
// A window covering the whole monitor reads to the shell as full screen, and
// the shell then never slides the taskbar back in over it; Chromium and
// Windows Terminal leave the same two pixels.
constexpr int kAutoHideRevealPx = 2;

// The client rect of a maximized custom-frame window, from the window rect
// Windows proposes in WM_NCCALCSIZE. Windows places a maximized WS_THICKFRAME
// window with its resize frame hanging `frame` past every edge of the monitor
// work area, so a client area equal to the window rect puts that much of the
// shell off screen on each side and under the taskbar. Taking the frame back
// off leaves exactly the work area. Pure, so it is testable without a monitor.
RECT MaximizedClientRect(const RECT& window, SIZE frame, const AutoHideEdges& auto_hide);

// The frame Windows hangs past the work area on each side of a maximized
// `window`: the sizing border plus the padded border, at the window's DPI.
SIZE MaximizedFrameThickness(HWND window);

// The edges of `monitor` that hold an auto-hiding appbar.
AutoHideEdges AutoHideAppbarEdges(HMONITOR monitor);

}  // namespace kelpie::windows
