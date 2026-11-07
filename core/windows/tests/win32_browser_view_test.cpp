#include "win32_browser_view.h"

#include <windows.h>

namespace {

HWND Fallback(HWND view) {
  return FindWindowExW(view, nullptr, L"STATIC", nullptr);
}

struct HostWindow {
  HWND handle = CreateWindowExW(0, L"STATIC", L"Browser view test",
      WS_OVERLAPPEDWINDOW | WS_VISIBLE, 0, 0, 160, 90,
      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  ~HostWindow() { if (handle != nullptr) DestroyWindow(handle); }
};

}  // namespace

int main() {
  // Own the parent window: the SSH/session desktop may itself be invisible.
  HostWindow host;
  if (host.handle == nullptr) return 5;
  kelpie::windows::Win32BrowserView view;
  const RECT bounds{0, 0, 160, 90};
  if (!view.Create(host.handle, GetModuleHandleW(nullptr), bounds, nullptr)) return 1;
  const LONG_PTR style = GetWindowLongPtrW(view.hwnd(), GWL_STYLE);
  if ((style & WS_CLIPCHILDREN) == 0 || (style & WS_CLIPSIBLINGS) == 0) return 2;
  const HWND fallback = Fallback(view.hwnd());
  if (fallback == nullptr || !IsWindowVisible(fallback)) return 3;
  view.ShowFallback(false);
  if (IsWindowVisible(fallback)) return 4;
  view.Destroy();
  return 0;
}
