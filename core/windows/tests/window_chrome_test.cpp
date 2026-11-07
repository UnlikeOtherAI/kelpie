#include "window_chrome.h"

#include <commctrl.h>

#include <iostream>

#include "maximized_frame.h"
#include "resource.h"
#include "theme/theme.h"

namespace {

LPARAM ScreenPoint(int x, int y) {
  return static_cast<LPARAM>((static_cast<unsigned int>(y) & 0xffffU) << 16U |
                             (static_cast<unsigned int>(x) & 0xffffU));
}

bool Expect(bool condition, const char* message) {
  if (condition) return true;
  std::cerr << message << std::endl;
  return false;
}

bool SameRect(const RECT& a, const RECT& b) {
  return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom;
}

RECT ClientOnScreen(HWND window) {
  RECT client{};
  GetClientRect(window, &client);
  MapWindowPoints(window, HWND_DESKTOP, reinterpret_cast<POINT*>(&client), 2);
  return client;
}

// Routes the frame messages the way Win32Shell::HandleMessage does, so the
// window below has the shell's borderless frame rather than a default one.
LRESULT CALLBACK ShellFrameProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  const auto* chrome =
      reinterpret_cast<const kelpie::windows::WindowChrome*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (chrome != nullptr && message == WM_NCCALCSIZE && wparam == TRUE) {
    return chrome->CalcClientArea(reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam));
  }
  if (chrome != nullptr && message == WM_NCHITTEST) return chrome->HitTest(wparam, lparam);
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

// Puts a hidden window where Windows maximizes it: WS_MAXIMIZE is what
// IsZoomed reads, and the frame hangs past every edge of the work area. It is
// never shown, because these tests run on a desktop someone is working at and
// ShowWindow(SW_MAXIMIZE) would cover it and take focus on every build.
void MaximizeHidden(HWND window, const RECT& work_area) {
  const SIZE frame = kelpie::windows::MaximizedFrameThickness(window);
  SetWindowLongPtrW(window, GWL_STYLE, GetWindowLongPtrW(window, GWL_STYLE) | WS_MAXIMIZE);
  SetWindowPos(window, nullptr, work_area.left - frame.cx, work_area.top - frame.cy,
               work_area.right - work_area.left + 2 * frame.cx,
               work_area.bottom - work_area.top + 2 * frame.cy,
               SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOACTIVATE);
}

void RestoreHidden(HWND window, const RECT& frame) {
  SetWindowLongPtrW(window, GWL_STYLE, GetWindowLongPtrW(window, GWL_STYLE) & ~WS_MAXIMIZE);
  SetWindowPos(window, nullptr, frame.left, frame.top, frame.right - frame.left,
               frame.bottom - frame.top, SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOACTIVATE);
}

// Maximized, Windows hangs the resize frame past every edge of the work area.
// The client area, and so the caption dots and the page, must land on the
// work area itself rather than eight pixels off screen and under the taskbar.
bool MaximizedClientAreaIsTheWorkArea(HINSTANCE instance) {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = ShellFrameProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = L"KelpieMaximizedFrameTest";
  RegisterClassW(&window_class);
  HWND window = CreateWindowExW(0, window_class.lpszClassName, L"Kelpie",
                                WS_OVERLAPPED | WS_THICKFRAME | WS_MINIMIZEBOX |
                                    WS_MAXIMIZEBOX | WS_SYSMENU,
                                100, 100, 900, 600, nullptr, nullptr, instance, nullptr);
  if (!Expect(window != nullptr, "maximize test window failed to create")) return false;
  kelpie::windows::WindowChrome chrome;
  chrome.Attach(window, instance);
  SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&chrome));
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);

  bool passed = true;
  RECT restored{};
  GetWindowRect(window, &restored);
  passed &= Expect(SameRect(ClientOnScreen(window), restored),
                   "restored window is no longer borderless");

  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  GetMonitorInfoW(monitor, &info);
  MaximizeHidden(window, info.rcWork);
  chrome.LayoutControls();
  const kelpie::windows::AutoHideEdges auto_hide = kelpie::windows::AutoHideAppbarEdges(monitor);
  RECT expected = info.rcWork;
  if (auto_hide.left) expected.left += kelpie::windows::kAutoHideRevealPx;
  if (auto_hide.top) expected.top += kelpie::windows::kAutoHideRevealPx;
  if (auto_hide.right) expected.right -= kelpie::windows::kAutoHideRevealPx;
  if (auto_hide.bottom) expected.bottom -= kelpie::windows::kAutoHideRevealPx;
  const RECT client = ClientOnScreen(window);
  passed &= Expect(IsZoomed(window) != FALSE, "window did not maximize");
  passed &= Expect(IsWindowVisible(window) == FALSE, "maximize test window was shown");
  passed &= Expect(SameRect(client, expected),
                   "maximized client area is not the monitor work area");

  RECT close_rect{};
  GetWindowRect(GetDlgItem(window, IDC_WINDOW_CLOSE), &close_rect);
  passed &= Expect(close_rect.right == expected.right && close_rect.left == expected.right - kelpie::windows::ui::Dip(window, 50),
                   "maximized close button does not meet the right work-area edge");
  passed &= Expect(close_rect.top == expected.top && close_rect.bottom == expected.top + chrome.TitleBarHeight(),
                   "maximized caption controls do not fit the title strip");
  const LPARAM close_centre = ScreenPoint((close_rect.left + close_rect.right) / 2,
                                          (close_rect.top + close_rect.bottom) / 2);
  passed &= Expect(SendMessageW(window, WM_NCHITTEST, 0, close_centre) == HTCLIENT,
                   "maximized caption controls are covered by the drag region");
  const LPARAM title_centre = ScreenPoint((expected.left + expected.right) / 2, expected.top + 5);
  passed &= Expect(SendMessageW(window, WM_NCHITTEST, 0, title_centre) == HTCAPTION,
                   "maximized title strip is not draggable");

  RestoreHidden(window, restored);
  passed &= Expect(SameRect(ClientOnScreen(window), restored),
                   "restoring from maximized kept the maximized inset");
  DestroyWindow(window);
  return passed;
}

}  // namespace

int main() {
  INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_LISTVIEW_CLASSES};
  if (!Expect(InitCommonControlsEx(&controls) != FALSE,
              "common controls failed to initialize")) {
    return 1;
  }

  HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = DefWindowProcW;
  window_class.hInstance = instance;
  window_class.lpszClassName = L"KelpieWindowChromeTest";
  RegisterClassW(&window_class);
  HWND window =
      CreateWindowExW(0, window_class.lpszClassName, L"Kelpie",
                      WS_OVERLAPPED | WS_THICKFRAME | WS_MINIMIZEBOX |
                          WS_MAXIMIZEBOX | WS_SYSMENU,
                      100, 100, 640, 480, nullptr, nullptr, instance, nullptr);
  if (!Expect(window != nullptr, "test window failed to create")) return 1;

  kelpie::windows::WindowChrome chrome;
  chrome.Attach(window, instance);
  chrome.LayoutControls();

  bool passed = true;
  passed &= Expect(GetDlgItem(window, IDC_WINDOW_CLOSE) != nullptr,
                   "close control was not created");
  passed &= Expect(GetDlgItem(window, IDC_WINDOW_MINIMIZE) != nullptr,
                   "minimize control was not created");
  passed &= Expect(GetDlgItem(window, IDC_WINDOW_MAXIMIZE) != nullptr,
                   "maximize control was not created");

  RECT window_rect{};
  GetWindowRect(window, &window_rect);
  passed &=
      Expect(chrome.HitTest(0, ScreenPoint(window_rect.left + 2,
                                           window_rect.top + 2)) == HTTOPLEFT,
             "top-left resize hit target is missing");
  passed &= Expect(
      chrome.HitTest(0, ScreenPoint((window_rect.left + window_rect.right) / 2,
                                    window_rect.top + 20)) == HTCAPTION,
      "title strip is not draggable");

  RECT close_rect{};
  GetWindowRect(GetDlgItem(window, IDC_WINDOW_CLOSE), &close_rect);
  passed &= Expect(
      chrome.HitTest(
          0, ScreenPoint((close_rect.left + close_rect.right) / 2,
                         (close_rect.top + close_rect.bottom) / 2)) == HTCLIENT,
      "window controls are covered by the drag region");

  DestroyWindow(window);
  passed &= MaximizedClientAreaIsTheWorkArea(instance);
  return passed ? 0 : 1;
}
