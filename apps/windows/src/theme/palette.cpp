#include "theme/palette.h"

#include <dwmapi.h>
#include <uxtheme.h>

#include <atomic>
#include <cstring>

namespace kelpie::windows::ui {
namespace {

// Documented in the Windows app-theme contract; 20 on Windows 10 2004 and
// later, 19 on the earlier builds that shipped it as an undocumented value.
constexpr DWORD kDwmUseImmersiveDarkMode = 20;
constexpr DWORD kDwmUseImmersiveDarkModeLegacy = 19;

// Cached so paint paths do not open a registry key per drawn control. Any
// theme change clears it through InvalidateAppearanceCache.
std::atomic<int> g_cached_dark{-1};

bool ReadAppsUseLightTheme(bool* light) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", 0,
                    KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD value = 1;
  DWORD size = sizeof(value);
  DWORD type = 0;
  const LSTATUS status =
      RegQueryValueExW(key, L"AppsUseLightTheme", nullptr, &type,
                       reinterpret_cast<LPBYTE>(&value), &size);
  RegCloseKey(key);
  if (status != ERROR_SUCCESS || type != REG_DWORD) return false;
  *light = value != 0;
  return true;
}

}  // namespace

bool HighContrast() {
  HIGHCONTRASTW state{sizeof(state)};
  return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(state), &state, 0) != FALSE &&
         (state.dwFlags & HCF_HIGHCONTRASTON) != 0;
}

bool DarkMode() {
  const int cached = g_cached_dark.load(std::memory_order_relaxed);
  if (cached >= 0) return cached != 0;
  bool light = true;
  // A missing value means the classic light theme, which is also the safe
  // default: light chrome stays legible under an unexpected system state.
  const bool dark = ReadAppsUseLightTheme(&light) && !light;
  g_cached_dark.store(dark ? 1 : 0, std::memory_order_relaxed);
  return dark;
}

Appearance CurrentAppearance() {
  if (HighContrast()) return Appearance::kHighContrast;
  return DarkMode() ? Appearance::kDark : Appearance::kLight;
}

Palette Colors() {
  switch (CurrentAppearance()) {
    case Appearance::kHighContrast:
      // System colours are the whole point of high contrast: the user has
      // chosen them and no product palette may override that choice.
      return {GetSysColor(COLOR_WINDOW),     GetSysColor(COLOR_WINDOW),
              GetSysColor(COLOR_HIGHLIGHT),  GetSysColor(COLOR_WINDOWTEXT),
              GetSysColor(COLOR_WINDOWTEXT), GetSysColor(COLOR_GRAYTEXT),
              GetSysColor(COLOR_HIGHLIGHT),  GetSysColor(COLOR_HIGHLIGHT)};
    case Appearance::kDark:
      return {RGB(32, 32, 36),    RGB(43, 44, 49),    RGB(56, 57, 63),
              RGB(62, 63, 69),    RGB(242, 242, 245), RGB(154, 156, 164),
              RGB(80, 140, 240),  RGB(96, 152, 246)};
    case Appearance::kLight:
      break;
  }
  return {RGB(246, 246, 248), RGB(255, 255, 255), RGB(238, 239, 243),
          RGB(211, 212, 217), RGB(39, 40, 45),    RGB(104, 106, 114),
          RGB(63, 124, 224),  RGB(52, 112, 214)};
}

bool IsAppearanceChange(UINT message, LPARAM lparam) {
  if (message == WM_THEMECHANGED || message == WM_SYSCOLORCHANGE) return true;
  if (message != WM_SETTINGCHANGE || lparam == 0) return false;
  const auto* area = reinterpret_cast<const wchar_t*>(lparam);
  return wcscmp(area, L"ImmersiveColorSet") == 0;
}

void InvalidateAppearanceCache() {
  g_cached_dark.store(-1, std::memory_order_relaxed);
}

void ApplyWindowAppearance(HWND window) {
  if (window == nullptr) return;
  const BOOL dark = DarkMode() ? TRUE : FALSE;
  if (FAILED(DwmSetWindowAttribute(window, kDwmUseImmersiveDarkMode, &dark, sizeof(dark)))) {
    DwmSetWindowAttribute(window, kDwmUseImmersiveDarkModeLegacy, &dark, sizeof(dark));
  }
}

void ApplyControlAppearance(HWND control) {
  if (control == nullptr) return;
  // Scrollbars and selection highlights inside EDIT and ListView are drawn by
  // the theme, not by our paint code, so they need this to follow the palette.
  SetWindowTheme(control, DarkMode() ? L"DarkMode_Explorer" : L"Explorer", nullptr);
}

}  // namespace kelpie::windows::ui
