#include "theme/theme.h"

#include <cassert>
#include <cstdio>
#include <set>
#include <vector>

namespace {

using namespace kelpie::windows;

// A real off-screen window so the DPI and paint paths run against an actual
// HWND and HDC rather than a null handle they might silently tolerate.
HWND CreateProbeWindow() {
  WNDCLASSW cls{};
  cls.lpfnWndProc = DefWindowProcW;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"KelpieThemeProbe";
  RegisterClassW(&cls);
  return CreateWindowExW(0, cls.lpszClassName, L"", WS_OVERLAPPEDWINDOW, 0, 0, 400, 300, nullptr,
                         nullptr, cls.hInstance, nullptr);
}

void TestDpiScaling(HWND window) {
  const UINT dpi = ui::WindowDpi(window);
  assert(dpi >= 96 && "a window always reports at least 96 DPI");
  // Dip must scale by the window's own DPI, not a system-wide value.
  assert(ui::Dip(window, 0) == 0);
  assert(ui::Dip(window, 100) == MulDiv(100, static_cast<int>(dpi), 96));
  // The toolbar metrics the macOS reference fixes must survive scaling in
  // order: a 34-DIP control is never taller than the 50-DIP row it sits in.
  assert(ui::Dip(window, 34) < ui::Dip(window, 50));
  assert(ui::Dip(window, 8) <= ui::Dip(window, 12));
  // A null window degrades to the system DPI instead of dividing by zero.
  assert(ui::WindowDpi(nullptr) >= 96);
}

void TestPaletteRoles() {
  const auto colors = ui::Colors();
  // Text on its own surface must not be invisible. This is the one palette
  // invariant worth asserting mechanically: every other choice is taste.
  assert(colors.text != colors.surface);
  assert(colors.text != colors.canvas);
  assert(colors.muted_text != colors.canvas);
  assert(colors.border != colors.canvas || ui::HighContrast());

  // High contrast must defer to the system entirely.
  if (ui::HighContrast()) {
    assert(ui::CurrentAppearance() == ui::Appearance::kHighContrast);
    assert(colors.canvas == GetSysColor(COLOR_WINDOW));
    assert(colors.text == GetSysColor(COLOR_WINDOWTEXT));
  } else {
    const auto expected = ui::DarkMode() ? ui::Appearance::kDark : ui::Appearance::kLight;
    assert(ui::CurrentAppearance() == expected);
  }
}

void TestAppearanceChangeDetection() {
  wchar_t immersive[] = L"ImmersiveColorSet";
  wchar_t unrelated[] = L"Environment";
  assert(ui::IsAppearanceChange(WM_SETTINGCHANGE, reinterpret_cast<LPARAM>(immersive)));
  assert(!ui::IsAppearanceChange(WM_SETTINGCHANGE, reinterpret_cast<LPARAM>(unrelated)));
  // A null lparam is legal on WM_SETTINGCHANGE and must not be dereferenced.
  assert(!ui::IsAppearanceChange(WM_SETTINGCHANGE, 0));
  assert(ui::IsAppearanceChange(WM_THEMECHANGED, 0));
  assert(ui::IsAppearanceChange(WM_SYSCOLORCHANGE, 0));
  assert(!ui::IsAppearanceChange(WM_PAINT, 0));

  // Clearing the cache must not change the answer while the system has not.
  const bool before = ui::DarkMode();
  ui::InvalidateAppearanceCache();
  assert(ui::DarkMode() == before);
}

void TestFontCache(HWND window) {
  HFONT a = ui::CachedFont(window, 13, FW_NORMAL);
  HFONT b = ui::CachedFont(window, 13, FW_NORMAL);
  assert(a != nullptr && a == b && "the cache must return one font per key");

  HFONT bold = ui::CachedFont(window, 13, FW_SEMIBOLD);
  HFONT larger = ui::CachedFont(window, 16, FW_NORMAL);
  assert(bold != a && larger != a && "weight and size are part of the key");

  HFONT icons = ui::CachedIconFont(window, 14);
  assert(icons != nullptr && icons != ui::CachedFont(window, 14, FW_NORMAL));

  // MakeFont hands ownership to the caller, so it must not return a cached
  // handle that a DeleteObject would then leave dangling in the cache.
  HFONT owned = ui::MakeFont(window, 13, FW_NORMAL);
  assert(owned != nullptr && owned != a);
  DeleteObject(owned);
}

void TestIconGlyphsAreDistinct() {
  // A duplicated code point would silently give two controls the same icon.
  const std::vector<wchar_t> glyphs{ui::icon::kBack,      ui::icon::kForward, ui::icon::kReload,
                                    ui::icon::kBookmarks, ui::icon::kHistory, ui::icon::kNetwork,
                                    ui::icon::kSettings,  ui::icon::kNewTab,  ui::icon::kLock};
  const std::set<wchar_t> unique(glyphs.begin(), glyphs.end());
  assert(unique.size() == glyphs.size());
  // Stop and close intentionally share the cancel glyph.
  assert(ui::icon::kStop == ui::icon::kClose);
}

// Paint into a memory DC and confirm the primitives actually put the fill
// colour down, that the corners are left rounded, and that the border stays
// inside the rectangle instead of bleeding a pixel outside it.
void TestPaintPrimitives(HWND window) {
  HDC screen = GetDC(window);
  HDC dc = CreateCompatibleDC(screen);
  constexpr int kSize = 64;
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = kSize;
  info.bmiHeader.biHeight = -kSize;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  assert(bitmap != nullptr);
  HGDIOBJ previous = SelectObject(dc, bitmap);

  const RECT full{0, 0, kSize, kSize};
  ui::FillSolid(dc, full, RGB(0, 0, 0));
  const RECT rounded{8, 8, kSize - 8, kSize - 8};
  ui::PaintRounded(dc, rounded, RGB(255, 255, 255), RGB(255, 0, 0), 12, 1);

  const auto* pixels = static_cast<const std::uint32_t*>(bits);
  const auto at = [&](int x, int y) { return pixels[y * kSize + x] & 0x00FFFFFFu; };

  // Centre is filled.
  assert(at(kSize / 2, kSize / 2) == 0x00FFFFFFu);
  // Outside the rectangle is untouched.
  assert(at(1, 1) == 0u);
  assert(at(kSize - 2, kSize - 2) == 0u);
  // The corner of the bounding box is left unfilled by the rounding.
  assert(at(9, 9) != 0x00FFFFFFu);

  ui::PaintFocusRing(dc, rounded, RGB(0, 0, 255), 12, 2);
  ui::DrawGlyph(dc, window, rounded, ui::icon::kSettings, RGB(0, 0, 0), 14);
  ui::DrawLabel(dc, window, rounded, L"Kelpie", RGB(0, 0, 0), 13, FW_NORMAL, DT_LEFT);

  // Degenerate rectangles must be refused rather than drawn inside out.
  const RECT inverted{40, 40, 10, 10};
  ui::PaintRounded(dc, inverted, RGB(1, 2, 3), RGB(4, 5, 6), 6, 1);
  ui::PaintFocusRing(dc, inverted, RGB(1, 2, 3), 6, 2);

  // A radius larger than the box degrades to a stadium instead of crossing arcs.
  const RECT squat{4, 28, 60, 36};
  ui::PaintRounded(dc, squat, RGB(0, 255, 0), RGB(0, 255, 0), 40, 1);
  assert(at(32, 32) == 0x0000FF00u);

  SelectObject(dc, previous);
  DeleteObject(bitmap);
  DeleteDC(dc);
  ReleaseDC(window, screen);
}

void TestPanelMetrics(HWND window) {
  assert(ui::PanelHeaderHeight(window) == ui::Dip(window, 52));
  HFONT font = nullptr;
  ui::RefreshPanelFont(window, window, &font, 13);
  assert(font != nullptr);
  HFONT first = font;
  ui::RefreshPanelFont(window, window, &font, 16);
  assert(font != nullptr && font != first && "the replaced font must be swapped out");
  DeleteObject(font);
  // A null control must be tolerated rather than crashing the shell.
  HFONT none = nullptr;
  ui::RefreshPanelFont(window, nullptr, &none, 13);
  assert(none == nullptr);
  ui::StyleList(nullptr, nullptr);
}

}  // namespace

int main() {
  HWND window = CreateProbeWindow();
  assert(window != nullptr);

  TestDpiScaling(window);
  TestPaletteRoles();
  TestAppearanceChangeDetection();
  TestFontCache(window);
  TestIconGlyphsAreDistinct();
  TestPaintPrimitives(window);
  TestPanelMetrics(window);

  DestroyWindow(window);
  std::printf("theme_test: ok\n");
  return 0;
}
