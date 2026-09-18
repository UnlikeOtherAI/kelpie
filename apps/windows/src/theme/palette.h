#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows::ui {

// `_WIN32_WINNT` stays at Vista for the CEF compatibility build, whose headers
// do not declare this later message.
constexpr UINT kDpiChangedMessage = 0x02E0;

enum class Appearance {
  kLight,
  kDark,
  kHighContrast,
};

// The named roles the whole shell paints with. They mirror the macOS app's
// semantic colours (`controlBackgroundColor`, `separatorColor`, `labelColor`,
// `secondaryLabelColor`, `selectedControlColor`) so the two platforms stay
// describable in the same terms rather than by literal RGB values.
struct Palette {
  COLORREF canvas;         // window chrome behind the toolbar and tab strip
  COLORREF surface;        // address field and icon-button fill
  COLORREF surface_hover;  // hover/pressed fill for those controls
  COLORREF border;         // hairline around surfaces and the window frame
  COLORREF text;           // primary label
  COLORREF muted_text;     // secondary label, inactive tab titles
  COLORREF accent;         // active tab indicator, selected control
  COLORREF focus;          // keyboard focus ring
};

bool HighContrast();

// True when the user's app theme is dark. Reads
// HKCU\...\Themes\Personalize\AppsUseLightTheme, the same value Explorer uses.
bool DarkMode();

Appearance CurrentAppearance();

Palette Colors();

// Whether `message`/`lparam` is a theme change the shell must repaint for:
// WM_SETTINGCHANGE carrying "ImmersiveColorSet", or WM_THEMECHANGED /
// WM_SYSCOLORCHANGE. Call `InvalidateAppearanceCache` before repainting.
bool IsAppearanceChange(UINT message, LPARAM lparam);

void InvalidateAppearanceCache();

// Applies the dark title bar and border to a top-level window, and the
// dark scrollbar/selection theme to a child control. Both are no-ops on
// Windows builds that do not support the attribute.
void ApplyWindowAppearance(HWND window);
void ApplyControlAppearance(HWND control);

}  // namespace kelpie::windows::ui
