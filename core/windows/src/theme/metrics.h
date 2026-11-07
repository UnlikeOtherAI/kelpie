#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows::ui {

// Per-window DPI. GDI's LOGPIXELSX is a single system-wide value and cannot
// describe a window that has been dragged onto a differently scaled monitor,
// so every metric in the shell goes through this.
UINT WindowDpi(HWND window);

// Scales a device-independent pixel count for `window`. The macOS reference
// metrics are expressed in points, which are the same numbers at 100%.
int Dip(HWND window, int value);

// A Segoe UI font sized for `window`'s DPI, owned by the caller, who must
// DeleteObject it. Use CachedFont for repeated paint work.
HFONT MakeFont(HWND window, int dip_size, int weight = FW_NORMAL);

// A shared font for hot paint paths, owned by the cache and valid for the
// process lifetime. Never DeleteObject the result. Entries are keyed by
// (dpi, size, weight) so a DPI change produces a new font rather than a
// stale one.
HFONT CachedFont(HWND window, int dip_size, int weight = FW_NORMAL);

// The icon font for toolbar and tab glyphs: Segoe Fluent Icons on Windows 11,
// falling back to Segoe MDL2 Assets. Owned by the cache, do not delete.
HFONT CachedIconFont(HWND window, int dip_size);

}  // namespace kelpie::windows::ui
