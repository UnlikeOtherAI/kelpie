#include "theme/paint.h"

#include <algorithm>
#include <mutex>

// GDI+ headers need IStream and PROPID, which WIN32_LEAN_AND_MEAN excludes,
// and they reference Gdiplus::min/max, which NOMINMAX removes. Supply both
// before including them rather than relaxing either project-wide define.
#include <objidl.h>

namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

namespace kelpie::windows::ui {
namespace {

// GDI+ is started on first use and deliberately never shut down. Calling
// GdiplusShutdown races any window still painting during teardown, and the
// single token costs nothing: the process exit reclaims it.
void EnsureGdiPlus() {
  static std::once_flag once;
  std::call_once(once, [] {
    Gdiplus::GdiplusStartupInput input;
    ULONG_PTR token = 0;
    Gdiplus::GdiplusStartup(&token, &input, nullptr);
  });
}

Gdiplus::Color ToGdiPlus(COLORREF color) {
  return Gdiplus::Color(255, GetRValue(color), GetGValue(color), GetBValue(color));
}

// A rounded-rectangle path in real coordinates. `radius` is clamped so a short
// control degrades to a stadium shape instead of producing crossed arcs.
void BuildRoundedPath(Gdiplus::GraphicsPath* path, const Gdiplus::RectF& bounds, float radius) {
  const float limit = std::min(bounds.Width, bounds.Height) / 2.0f;
  const float r = std::clamp(radius, 0.0f, std::max(0.0f, limit));
  if (r <= 0.1f) {
    path->AddRectangle(bounds);
    return;
  }
  const float d = r * 2.0f;
  path->AddArc(bounds.X, bounds.Y, d, d, 180.0f, 90.0f);
  path->AddArc(bounds.GetRight() - d, bounds.Y, d, d, 270.0f, 90.0f);
  path->AddArc(bounds.GetRight() - d, bounds.GetBottom() - d, d, d, 0.0f, 90.0f);
  path->AddArc(bounds.X, bounds.GetBottom() - d, d, d, 90.0f, 90.0f);
  path->CloseFigure();
}

}  // namespace

void FillSolid(HDC dc, const RECT& rect, COLORREF color) {
  HBRUSH brush = CreateSolidBrush(color);
  FillRect(dc, &rect, brush);
  DeleteObject(brush);
}

void PaintBrowserTab(HDC dc, RECT rect, COLORREF fill, COLORREF border, int radius) {
  EnsureGdiPlus();
  Gdiplus::Graphics graphics(dc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  const float l = static_cast<float>(rect.left), r = static_cast<float>(rect.right);
  const float t = static_cast<float>(rect.top)+0.5f, b = static_cast<float>(rect.bottom);
  const float c = static_cast<float>(radius);
  Gdiplus::GraphicsPath path;
  path.AddBezier(l,b,l+c,b,l+c,b-c,l+c,b-c);
  path.AddLine(l+c,b-c,l+c,t+c);
  path.AddBezier(l+c,t+c,l+c,t,l+c*2,t,l+c*2,t);
  path.AddLine(l+c*2,t,r-c*2,t);
  path.AddBezier(r-c*2,t,r-c,t,r-c,t+c,r-c,t+c);
  path.AddLine(r-c,t+c,r-c,b-c);
  path.AddBezier(r-c,b-c,r-c,b,r,b,r,b);
  Gdiplus::SolidBrush brush(ToGdiPlus(fill));
  graphics.FillPath(&brush, &path);
  Gdiplus::Pen pen(ToGdiPlus(border), 1.0f);
  graphics.DrawPath(&pen, &path);
}

void PaintRounded(HDC dc, RECT rect, COLORREF fill, COLORREF border, int radius,
                  int border_width) {
  if (rect.right <= rect.left || rect.bottom <= rect.top) return;
  EnsureGdiPlus();
  Gdiplus::Graphics graphics(dc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);

  // A stroke straddles its path, so inset by half the pen width to keep the
  // border inside `rect` and land it on whole pixels.
  const float inset = border_width > 0 ? static_cast<float>(border_width) / 2.0f : 0.0f;
  const Gdiplus::RectF bounds(static_cast<float>(rect.left) + inset,
                              static_cast<float>(rect.top) + inset,
                              static_cast<float>(rect.right - rect.left) - inset * 2.0f,
                              static_cast<float>(rect.bottom - rect.top) - inset * 2.0f);
  if (bounds.Width <= 0.0f || bounds.Height <= 0.0f) return;

  Gdiplus::GraphicsPath path;
  BuildRoundedPath(&path, bounds, static_cast<float>(radius));

  Gdiplus::SolidBrush brush(ToGdiPlus(fill));
  graphics.FillPath(&brush, &path);
  if (border_width > 0 && border != fill) {
    Gdiplus::Pen pen(ToGdiPlus(border), static_cast<float>(border_width));
    graphics.DrawPath(&pen, &path);
  }
}

void PaintFocusRing(HDC dc, RECT rect, COLORREF color, int radius, int width) {
  if (width <= 0 || rect.right <= rect.left || rect.bottom <= rect.top) return;
  EnsureGdiPlus();
  Gdiplus::Graphics graphics(dc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);

  const float offset = static_cast<float>(width) / 2.0f;
  const Gdiplus::RectF bounds(static_cast<float>(rect.left) - offset,
                              static_cast<float>(rect.top) - offset,
                              static_cast<float>(rect.right - rect.left) + offset * 2.0f,
                              static_cast<float>(rect.bottom - rect.top) + offset * 2.0f);
  if (bounds.Width <= 0.0f || bounds.Height <= 0.0f) return;

  Gdiplus::GraphicsPath path;
  BuildRoundedPath(&path, bounds, static_cast<float>(radius) + offset);
  Gdiplus::Pen pen(ToGdiPlus(color), static_cast<float>(width));
  graphics.DrawPath(&pen, &path);
}

void DrawGlyph(HDC dc, HWND owner, const RECT& rect, wchar_t glyph, COLORREF color,
               int dip_size) {
  HGDIOBJ previous = SelectObject(dc, CachedIconFont(owner, dip_size));
  const int previous_mode = SetBkMode(dc, TRANSPARENT);
  const COLORREF previous_color = SetTextColor(dc, color);
  RECT target = rect;
  DrawTextW(dc, &glyph, 1, &target, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  SetTextColor(dc, previous_color);
  SetBkMode(dc, previous_mode);
  SelectObject(dc, previous);
}

void DrawLabel(HDC dc, HWND owner, const RECT& rect, const wchar_t* text, COLORREF color,
               int dip_size, int weight, UINT align) {
  if (text == nullptr) return;
  HGDIOBJ previous = SelectObject(dc, CachedFont(owner, dip_size, weight));
  const int previous_mode = SetBkMode(dc, TRANSPARENT);
  const COLORREF previous_color = SetTextColor(dc, color);
  RECT target = rect;
  DrawTextW(dc, text, -1, &target,
            align | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
  SetTextColor(dc, previous_color);
  SetBkMode(dc, previous_mode);
  SelectObject(dc, previous);
}

}  // namespace kelpie::windows::ui
