#include "theme/panels.h"

#include <commctrl.h>

#include <algorithm>

#include "theme/paint.h"

namespace kelpie::windows::ui {
namespace {

// `_WIN32_WINNT` stays at Vista for the CEF compatibility build, so the
// per-DPI frame metric is resolved at run time like GetDpiForWindow.
BOOL AdjustForDpi(RECT* rect, DWORD style, DWORD ex_style, UINT dpi) {
  using AdjustFn = BOOL(WINAPI*)(LPRECT, DWORD, BOOL, DWORD, UINT);
  static const auto adjust = reinterpret_cast<AdjustFn>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "AdjustWindowRectExForDpi"));
  if (adjust != nullptr) return adjust(rect, style, FALSE, ex_style, dpi);
  return AdjustWindowRectEx(rect, style, FALSE, ex_style);
}

SIZE OuterSize(UINT dpi, SIZE client_dip, DWORD style, DWORD ex_style) {
  RECT rect{0, 0, MulDiv(client_dip.cx, static_cast<int>(dpi), 96),
            MulDiv(client_dip.cy, static_cast<int>(dpi), 96)};
  AdjustForDpi(&rect, style, ex_style, dpi);
  return {rect.right - rect.left, rect.bottom - rect.top};
}

}  // namespace

void StyleList(HWND list, HFONT font) {
  if (list == nullptr) return;
  // Full-row selection matches the macOS sheets, whose rows are clickable
  // across their whole width rather than on the label text alone.
  ListView_SetExtendedListViewStyle(list, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER |
                                              LVS_EX_LABELTIP | LVS_EX_INFOTIP);
  SendMessageW(list, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  const auto colors = Colors();
  ListView_SetBkColor(list, colors.surface);
  ListView_SetTextBkColor(list, colors.surface);
  ListView_SetTextColor(list, colors.text);
  ApplyControlAppearance(list);
  ApplyControlAppearance(ListView_GetHeader(list));
}

bool AnswerEmptyMarkup(LPARAM lparam, const wchar_t* message) {
  auto* markup = reinterpret_cast<NMLVEMPTYMARKUP*>(lparam);
  if (markup == nullptr || message == nullptr) return false;
  markup->dwFlags = EMF_CENTERED;
  wcsncpy_s(markup->szMarkup, message, _TRUNCATE);
  return true;
}

RECT CenteredWindowRect(const RECT& owner, const RECT& work_area, SIZE size) {
  const LONG work_width = work_area.right - work_area.left;
  const LONG work_height = work_area.bottom - work_area.top;
  const LONG width = std::clamp<LONG>(size.cx, 0, std::max<LONG>(work_width, 0));
  const LONG height = std::clamp<LONG>(size.cy, 0, std::max<LONG>(work_height, 0));
  const LONG centre_x = owner.left + (owner.right - owner.left) / 2;
  const LONG centre_y = owner.top + (owner.bottom - owner.top) / 2;
  const LONG left = std::clamp<LONG>(centre_x - width / 2, work_area.left, work_area.right - width);
  const LONG top = std::clamp<LONG>(centre_y - height / 2, work_area.top, work_area.bottom - height);
  return {left, top, left + width, top + height};
}

RECT OwnedWindowRect(HWND owner, SIZE client_dip, DWORD style, DWORD ex_style) {
  MONITORINFO monitor{sizeof(monitor)};
  const HMONITOR handle = owner != nullptr ? MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST)
                                           : MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  GetMonitorInfoW(handle, &monitor);
  RECT anchor = monitor.rcWork;
  // A minimized owner reports its taskbar placeholder; centre on its monitor.
  if (owner != nullptr && !IsIconic(owner)) GetWindowRect(owner, &anchor);
  const SIZE size = OuterSize(WindowDpi(owner), client_dip, style, ex_style);
  return CenteredWindowRect(anchor, monitor.rcWork, size);
}

SIZE OuterSizeForClient(HWND window, SIZE client_dip, DWORD style, DWORD ex_style) {
  return OuterSize(WindowDpi(window), client_dip, style, ex_style);
}

void ApplySuggestedDpiRect(HWND window, LPARAM lparam) {
  const auto* suggested = reinterpret_cast<const RECT*>(lparam);
  if (window == nullptr || suggested == nullptr) return;
  SetWindowPos(window, nullptr, suggested->left, suggested->top, suggested->right - suggested->left,
               suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
}

}  // namespace kelpie::windows::ui
