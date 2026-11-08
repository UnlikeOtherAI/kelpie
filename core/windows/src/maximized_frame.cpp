#include "maximized_frame.h"

#include <shellapi.h>

#include "theme/metrics.h"

namespace kelpie::windows {
namespace {

// ABM_GETAUTOHIDEBAREX (Windows 8+). The shell builds against a Vista SDK
// floor, where shellapi.h leaves it undefined.
constexpr DWORD kGetAutoHideBarEx = 0x0000000b;

int MetricForDpi(int index, UINT dpi) {
  // GetSystemMetricsForDpi is Windows 10 1607+, so it is resolved at run time
  // like GetDpiForWindow in theme/metrics.cpp. Without it the system-DPI
  // metric is also the one Windows maximizes with.
  using GetSystemMetricsForDpiFn = int(WINAPI*)(int, UINT);
  static const auto for_dpi = reinterpret_cast<GetSystemMetricsForDpiFn>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetSystemMetricsForDpi"));
  return for_dpi != nullptr ? for_dpi(index, dpi) : GetSystemMetrics(index);
}

}  // namespace

RECT MaximizedClientRect(const RECT& window, SIZE frame, const AutoHideEdges& auto_hide) {
  RECT client{window.left + frame.cx, window.top + frame.cy, window.right - frame.cx,
              window.bottom - frame.cy};
  if (auto_hide.left) client.left += kAutoHideRevealPx;
  if (auto_hide.top) client.top += kAutoHideRevealPx;
  if (auto_hide.right) client.right -= kAutoHideRevealPx;
  if (auto_hide.bottom) client.bottom -= kAutoHideRevealPx;
  return client;
}

SIZE MaximizedFrameThickness(HWND window) {
  const UINT dpi = ui::WindowDpi(window);
  // There is no SM_CYPADDEDBORDER: the padded border is the same on both axes.
  const int padding = MetricForDpi(SM_CXPADDEDBORDER, dpi);
  return {MetricForDpi(SM_CXFRAME, dpi) + padding, MetricForDpi(SM_CYFRAME, dpi) + padding};
}

AutoHideEdges AutoHideAppbarEdges(HMONITOR monitor) {
  AutoHideEdges edges;
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (monitor == nullptr || !GetMonitorInfoW(monitor, &info)) return edges;
  // An auto-hide bar reserves no work area, so the monitor rect is what it
  // sits against. The EX query is per monitor; the plain one asks only about
  // the primary display.
  const auto holds_bar = [&info](UINT edge) {
    APPBARDATA bar{};
    bar.cbSize = sizeof(bar);
    bar.uEdge = edge;
    bar.rc = info.rcMonitor;
    return SHAppBarMessage(kGetAutoHideBarEx, &bar) != 0;
  };
  edges.left = holds_bar(ABE_LEFT);
  edges.top = holds_bar(ABE_TOP);
  edges.right = holds_bar(ABE_RIGHT);
  edges.bottom = holds_bar(ABE_BOTTOM);
  return edges;
}

}  // namespace kelpie::windows
