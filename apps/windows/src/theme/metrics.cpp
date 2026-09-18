#include "theme/metrics.h"

#include <map>
#include <mutex>
#include <tuple>

namespace kelpie::windows::ui {
namespace {

constexpr const wchar_t* kUiFace = L"Segoe UI";
// Windows 11's icon face, with the Windows 10 face as the fallback. Both carry
// the same code points for the glyphs the shell uses.
constexpr const wchar_t* kIconFace = L"Segoe Fluent Icons";
constexpr const wchar_t* kIconFaceLegacy = L"Segoe MDL2 Assets";

struct FontKey {
  UINT dpi;
  int size;
  int weight;
  bool icon;

  bool operator<(const FontKey& other) const {
    return std::tie(dpi, size, weight, icon) <
           std::tie(other.dpi, other.size, other.weight, other.icon);
  }
};

std::mutex g_font_mutex;
std::map<FontKey, HFONT> g_fonts;

bool FaceInstalled(const wchar_t* face) {
  LOGFONTW probe{};
  probe.lfCharSet = DEFAULT_CHARSET;
  wcsncpy_s(probe.lfFaceName, face, _TRUNCATE);
  bool found = false;
  HDC dc = GetDC(nullptr);
  if (dc == nullptr) return false;
  EnumFontFamiliesExW(
      dc, &probe,
      [](const LOGFONTW*, const TEXTMETRICW*, DWORD, LPARAM param) -> int {
        *reinterpret_cast<bool*>(param) = true;
        return 0;
      },
      reinterpret_cast<LPARAM>(&found), 0);
  ReleaseDC(nullptr, dc);
  return found;
}

const wchar_t* IconFace() {
  // Resolved once: the installed font set does not change while the app runs,
  // and EnumFontFamiliesEx is far too costly for a paint path.
  static const wchar_t* face = FaceInstalled(kIconFace) ? kIconFace : kIconFaceLegacy;
  return face;
}

HFONT CreateScaledFont(UINT dpi, int dip_size, int weight, const wchar_t* face) {
  return CreateFontW(-MulDiv(dip_size, static_cast<int>(dpi), 96), 0, 0, 0, weight, FALSE, FALSE,
                     FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, face);
}

HFONT Cached(HWND window, int dip_size, int weight, bool icon) {
  const FontKey key{WindowDpi(window), dip_size, weight, icon};
  const std::lock_guard<std::mutex> lock(g_font_mutex);
  const auto existing = g_fonts.find(key);
  if (existing != g_fonts.end()) return existing->second;
  HFONT font = CreateScaledFont(key.dpi, dip_size, weight, icon ? IconFace() : kUiFace);
  if (font == nullptr) return static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
  g_fonts.emplace(key, font);
  return font;
}

}  // namespace

UINT WindowDpi(HWND window) {
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
  return dpi <= 0 ? 96U : static_cast<UINT>(dpi);
}

int Dip(HWND window, int value) {
  return MulDiv(value, static_cast<int>(WindowDpi(window)), 96);
}

HFONT MakeFont(HWND window, int dip_size, int weight) {
  return CreateScaledFont(WindowDpi(window), dip_size, weight, kUiFace);
}

HFONT CachedFont(HWND window, int dip_size, int weight) {
  return Cached(window, dip_size, weight, false);
}

HFONT CachedIconFont(HWND window, int dip_size) {
  return Cached(window, dip_size, FW_NORMAL, true);
}

}  // namespace kelpie::windows::ui
