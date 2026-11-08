#include "native_window_control.h"
#include <iostream>

namespace {
bool SameRect(const RECT& a, const RECT& b) {
  return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom;
}
}

int main() {
  const HINSTANCE instance = GetModuleHandleW(nullptr);
  const HWND host = CreateWindowExW(0, L"STATIC", L"Host", WS_OVERLAPPEDWINDOW,
      100, 100, 800, 600, nullptr, nullptr, instance, nullptr);
  const HWND shell = CreateWindowExW(0, L"STATIC", L"Browser shell", WS_CHILD,
      0, 0, 700, 500, host, nullptr, instance, nullptr);
  const HWND browser = CreateWindowExW(0, L"STATIC", L"Browser", WS_CHILD,
      0, 0, 400, 200, shell, nullptr, instance, nullptr);
  if (!host || !shell || !browser) return 1;
  kelpie::windows::NativeWindowControl control;
  if (!control.Create(instance, browser, 400, 200)) return 2;
  RECT before{}, after{};
  GetWindowRect(host, &before);
  bool passed = !control.Resize(500, 300) && !control.SetFullscreen(true);
  GetWindowRect(host, &after);
  passed = passed && SameRect(before, after) && !control.fullscreen();

  // A detached browser may manage its own window without borrowing its former host.
  SetParent(shell, nullptr);
  SetWindowLongPtrW(shell, GWL_STYLE, WS_OVERLAPPEDWINDOW);
  passed = passed && control.Resize(400, 200);
  GetWindowRect(host, &after);
  passed = passed && SameRect(before, after);
  control.Shutdown();
  DestroyWindow(shell);
  DestroyWindow(host);
  if (!passed) std::cerr << "Browser window control crossed its host boundary\n";
  return passed ? 0 : 1;
}
