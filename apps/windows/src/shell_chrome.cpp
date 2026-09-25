#include "win32_shell.h"

#include <commctrl.h>
#include <windowsx.h>
#include "../resources/resource.h"
#include "theme/theme.h"

namespace kelpie::windows {

void Win32Shell::SetPageColor(COLORREF color) {
  BOOL animations = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0);
  if (!chrome_transition_.Retarget(color, GetTickCount64(), animations && !ui::HighContrast())) return;
  UpdateChromePalette();
  if (chrome_transition_.Active(GetTickCount64())) SetTimer(hwnd_, 2, 16, nullptr);
}

void Win32Shell::UpdateChromePalette() {
  chrome_palette_ = ui::ChromeColors(chrome_transition_.Color(GetTickCount64()));
  window_chrome_.SetPalette(chrome_palette_);
  url_bar_.SetPalette(chrome_palette_);
  favorites_bar_.SetPalette(chrome_palette_);
  if (!hwnd_) return;
  // Invalidate just native chrome, never the GPU-backed renderer subtree.
  RECT bounds{};
  GetClientRect(hwnd_, &bounds);
  bounds.bottom = window_chrome_.TitleBarHeight()+url_bar_.Height()+favorites_bar_.Height()+1;
  RedrawWindow(hwnd_, &bounds, nullptr, RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
}

void Win32Shell::PaintTabStrip(HDC target) const {
  RECT bounds{};
  GetClientRect(tab_strip_, &bounds);
  if (bounds.right <= 0 || bounds.bottom <= 0) return;
  // One buffered frame owns the strip background and silhouettes. The native
  // control remains responsible for selection, accessibility and overflow.
  HDC dc = CreateCompatibleDC(target);
  HBITMAP bitmap = CreateCompatibleBitmap(target, bounds.right, bounds.bottom);
  const auto old = SelectObject(dc, bitmap);
  ui::FillSolid(dc, bounds, chrome_palette_.caption);
  auto paint = [&](std::size_t index) {
    RECT rect{};
    if (!TabCtrl_GetItemRect(tab_strip_, static_cast<int>(index), &rect)) return;
    rect.top = 0;
    rect.bottom = bounds.bottom;
    DRAWITEMSTRUCT item{};
    item.CtlID = IDC_TAB_STRIP;
    item.itemID = static_cast<UINT>(index);
    item.hDC = dc;
    item.rcItem = rect;
    DrawControl(item);
  };
  for (std::size_t i=0; i<tabs_.size(); ++i) if (!tabs_[i].active) paint(i);
  for (std::size_t i=0; i<tabs_.size(); ++i) if (tabs_[i].active) paint(i);
  BitBlt(target, 0, 0, bounds.right, bounds.bottom, dc, 0, 0, SRCCOPY);
  SelectObject(dc, old);
  DeleteObject(bitmap);
  DeleteDC(dc);
}

LRESULT CALLBACK Win32Shell::NewTabProc(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam, UINT_PTR subclass_id, DWORD_PTR data) {
  auto* self = reinterpret_cast<Win32Shell*>(data);
  if (message == WM_NCHITTEST && self) {
    const auto hit = self->window_chrome_.HitTest(wparam, lparam);
    if (hit >= HTLEFT && hit <= HTBOTTOMRIGHT) return HTTRANSPARENT;
  }
  if (message == WM_CONTEXTMENU && self) { self->ShowNewTabMenu(); return 0; }
  if (message == WM_NCDESTROY) RemoveWindowSubclass(hwnd, &Win32Shell::NewTabProc, subclass_id);
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace kelpie::windows
