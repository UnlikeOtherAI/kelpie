#include "win32_browser_view.h"

#include <windows.h>

namespace {

HWND Fallback(HWND view) {
  return FindWindowExW(view, nullptr, L"STATIC", nullptr);
}

}  // namespace

int main() {
  kelpie::windows::Win32BrowserView view;
  const RECT bounds{0, 0, 160, 90};
  if (!view.Create(GetDesktopWindow(), GetModuleHandleW(nullptr), bounds, nullptr)) return 1;
  const LONG_PTR style = GetWindowLongPtrW(view.hwnd(), GWL_STYLE);
  if ((style & WS_CLIPCHILDREN) == 0 || (style & WS_CLIPSIBLINGS) == 0) return 2;
  const HWND fallback = Fallback(view.hwnd());
  if (fallback == nullptr || !IsWindowVisible(fallback)) return 3;
  view.ShowFallback(false);
  if (IsWindowVisible(fallback)) return 4;
  view.Destroy();
  return 0;
}
