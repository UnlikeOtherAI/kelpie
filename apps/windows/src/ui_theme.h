#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>

namespace kelpie::windows::ui {

// `_WIN32_WINNT` stays at Vista for the CEF 120 compatibility build, whose
// headers do not declare this later message.
constexpr UINT kDpiChangedMessage = 0x02E0;

struct Palette {
  COLORREF canvas;
  COLORREF surface;
  COLORREF surface_hover;
  COLORREF border;
  COLORREF text;
  COLORREF muted_text;
  COLORREF accent;
  COLORREF focus;
};

inline bool HighContrast() {
  HIGHCONTRASTW state{sizeof(state)};
  return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(state), &state, 0) != FALSE &&
         (state.dwFlags & HCF_HIGHCONTRASTON) != 0;
}

inline Palette Colors() {
  if (HighContrast()) {
    return {GetSysColor(COLOR_WINDOW), GetSysColor(COLOR_WINDOW), GetSysColor(COLOR_HIGHLIGHT),
            GetSysColor(COLOR_WINDOWTEXT), GetSysColor(COLOR_WINDOWTEXT), GetSysColor(COLOR_GRAYTEXT),
            GetSysColor(COLOR_HIGHLIGHT), GetSysColor(COLOR_HIGHLIGHT)};
  }
  return {RGB(246, 246, 248), RGB(255, 255, 255), RGB(238, 239, 243), RGB(211, 212, 217),
          RGB(39, 40, 45), RGB(104, 106, 114), RGB(63, 124, 224), RGB(52, 112, 214)};
}

inline UINT WindowDpi(HWND window) {
  using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
  static const auto get_dpi_for_window = reinterpret_cast<GetDpiForWindowFn>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"));
  if (window != nullptr && get_dpi_for_window != nullptr) {
    const UINT dpi = get_dpi_for_window(window);
    if (dpi != 0) return dpi;
  }
  HDC dc = window == nullptr ? nullptr : GetDC(window);
  const int dpi = dc == nullptr ? 96 : GetDeviceCaps(dc, LOGPIXELSX);
  if (dc != nullptr) ReleaseDC(window, dc);
  return static_cast<UINT>(dpi);
}

inline int Dip(HWND window, int value) {
  return MulDiv(value, static_cast<int>(WindowDpi(window)), 96);
}

inline HFONT MakeFont(HWND window, int dip_size, int weight = FW_NORMAL) {
  return CreateFontW(-Dip(window, dip_size), 0, 0, 0, weight, FALSE, FALSE, FALSE,
                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
}

inline void PaintRounded(HDC dc, RECT rect, COLORREF fill, COLORREF border, int radius, int border_width = 1) {
  HBRUSH brush = CreateSolidBrush(fill);
  HPEN pen = CreatePen(PS_SOLID, border_width, border);
  HGDIOBJ old_brush = SelectObject(dc, brush);
  HGDIOBJ old_pen = SelectObject(dc, pen);
  RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, radius * 2, radius * 2);
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);
}

inline void DrawGlyph(HDC dc, HWND owner, const RECT& rect, wchar_t glyph, COLORREF color,
                      int dip_size = 15) {
  HFONT font = MakeFont(owner, dip_size, FW_SEMIBOLD);
  HGDIOBJ old = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, color);
  DrawTextW(dc, &glyph, 1, const_cast<RECT*>(&rect), DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  SelectObject(dc, old);
  DeleteObject(font);
}

}  // namespace kelpie::windows::ui


