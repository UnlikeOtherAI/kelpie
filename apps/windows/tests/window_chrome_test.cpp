#include "window_chrome.h"

#include <commctrl.h>

#include <iostream>

#include "resource.h"

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
  return passed ? 0 : 1;
}
