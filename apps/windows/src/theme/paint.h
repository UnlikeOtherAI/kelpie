#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "theme/metrics.h"
#include "theme/palette.h"

namespace kelpie::windows::ui {

// Fills `rect` with a solid colour. GDI is used deliberately: a rectangle has
// no edges to antialias, so GDI+ would only cost time.
void FillSolid(HDC dc, const RECT& rect, COLORREF color);

// Browser tab silhouette: rounded shoulders and outward feet, open at its base.
void PaintBrowserTab(HDC dc, RECT rect, COLORREF fill, COLORREF border, int radius);

// An antialiased rounded rectangle. The macOS controls this mirrors are
// CALayer-backed with smooth corners, and GDI's RoundRect stair-steps badly
// at the 8- and 15-point radii the toolbar uses.
void PaintRounded(HDC dc, RECT rect, COLORREF fill, COLORREF border, int radius,
                  int border_width = 1);

// A focus ring drawn just outside `rect`, matching the keyboard focus
// affordance on the macOS address field.
void PaintFocusRing(HDC dc, RECT rect, COLORREF color, int radius, int width);

// Draws one icon-font glyph centred in `rect`. `dip_size` is the glyph's
// device-independent point size; the font comes from the shared cache.
void DrawGlyph(HDC dc, HWND owner, const RECT& rect, wchar_t glyph, COLORREF color,
               int dip_size = 15);

// Draws a single line of UI text, vertically centred, clipped with an
// ellipsis. `weight` is a GDI FW_* value.
void DrawLabel(HDC dc, HWND owner, const RECT& rect, const wchar_t* text, COLORREF color,
               int dip_size, int weight = FW_NORMAL, UINT align = DT_LEFT);

}  // namespace kelpie::windows::ui
