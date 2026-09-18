#include "window_chrome.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>

#include "../resources/resource.h"

namespace kelpie::windows {
namespace {

constexpr int kTitleBarHeight = 38;
constexpr int kResizeBorderWidth = 8;
constexpr int kControlBoxSize = 20;
constexpr int kControlDiameter = 14;
constexpr int kControlGap = 4;
constexpr int kControlInset = 12;
constexpr COLORREF kChromeBackground = RGB(246, 246, 248);
constexpr COLORREF kActiveBorder = RGB(190, 190, 194);
constexpr COLORREF kInactiveBorder = RGB(216, 216, 220);
constexpr COLORREF kCloseColor = RGB(255, 95, 87);
constexpr COLORREF kMinimizeColor = RGB(254, 188, 46);
constexpr COLORREF kMaximizeColor = RGB(40, 200, 64);
constexpr COLORREF kInactiveControlColor = RGB(184, 184, 184);
#ifdef DWMWA_WINDOW_CORNER_PREFERENCE
constexpr DWMWINDOWATTRIBUTE kDwmWindowCornerPreferenceAttribute =
    DWMWA_WINDOW_CORNER_PREFERENCE;
#else
constexpr DWMWINDOWATTRIBUTE kDwmWindowCornerPreferenceAttribute =
    static_cast<DWMWINDOWATTRIBUTE>(33);
#endif
#ifdef DWMWA_BORDER_COLOR
constexpr DWMWINDOWATTRIBUTE kDwmBorderColorAttribute = DWMWA_BORDER_COLOR;
#else
constexpr DWMWINDOWATTRIBUTE kDwmBorderColorAttribute =
    static_cast<DWMWINDOWATTRIBUTE>(34);
#endif
#ifdef DWMWCP_ROUND
constexpr DWORD kDwmRound = DWMWCP_ROUND;
#else
constexpr DWORD kDwmRound = 2;
#endif
#ifdef DWMWCP_DONOTROUND
constexpr DWORD kDwmDoNotRound = DWMWCP_DONOTROUND;
#else
constexpr DWORD kDwmDoNotRound = 1;
#endif

bool IsControlId(UINT id) {
  return id == IDC_WINDOW_CLOSE || id == IDC_WINDOW_MINIMIZE ||
         id == IDC_WINDOW_MAXIMIZE;
}

}  // namespace

void WindowChrome::Attach(HWND window, HINSTANCE instance) {
  window_ = window;
  if (window_ != nullptr) {
    HDC device_context = GetDC(window_);
    if (device_context != nullptr) {
      SetDpi(static_cast<UINT>(GetDeviceCaps(device_context, LOGPIXELSX)));
      ReleaseDC(window_, device_context);
    }
  }
  struct ControlDefinition {
    int id;
    const wchar_t* label;
    HWND* handle;
  };
  ControlDefinition controls[] = {
      {IDC_WINDOW_CLOSE, L"Close", &close_button_},
      {IDC_WINDOW_MINIMIZE, L"Minimize", &minimize_button_},
      {IDC_WINDOW_MAXIMIZE, L"Maximize", &maximize_button_},
  };
  for (auto& control : controls) {
    *control.handle = CreateWindowExW(
        0, L"BUTTON", control.label,
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 0, 0, 0, 0, window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(control.id)), instance,
        nullptr);
    if (*control.handle != nullptr) {
      SetWindowSubclass(*control.handle, &WindowChrome::ControlProc,
                        static_cast<UINT_PTR>(control.id),
                        reinterpret_cast<DWORD_PTR>(this));
    }
  }
}

void WindowChrome::Draw(HDC device_context) const {
  if (window_ == nullptr) return;
  RECT rect{};
  GetClientRect(window_, &rect);
  const int title_bar_height = TitleBarHeight();
  RECT title_rect{rect.left, rect.top, rect.right,
                  std::min(rect.bottom, static_cast<LONG>(title_bar_height))};
  HBRUSH chrome_brush = CreateSolidBrush(kChromeBackground);
  FillRect(device_context, &title_rect, chrome_brush);
  DeleteObject(chrome_brush);

  const COLORREF separator_color = active_ ? kActiveBorder : kInactiveBorder;
  HPEN separator_pen = CreatePen(PS_SOLID, 1, separator_color);
  HGDIOBJ old_pen = SelectObject(device_context, separator_pen);
  MoveToEx(device_context, rect.left, title_rect.bottom - 1, nullptr);
  LineTo(device_context, rect.right, title_rect.bottom - 1);
  SelectObject(device_context, old_pen);
  DeleteObject(separator_pen);

  wchar_t title[512]{};
  GetWindowTextW(window_, title,
                 static_cast<int>(sizeof(title) / sizeof(title[0])));
  RECT text_rect{Scale(88), 0, rect.right - Scale(88), title_bar_height};
  SetBkMode(device_context, TRANSPARENT);
  SetTextColor(device_context, RGB(74, 74, 78));
  HGDIOBJ old_font =
      SelectObject(device_context, GetStockObject(DEFAULT_GUI_FONT));
  DrawTextW(
      device_context, title, -1, &text_rect,
      DT_CENTER | DT_END_ELLIPSIS | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
  SelectObject(device_context, old_font);

  if (!IsZoomed(window_)) {
    HBRUSH border_brush = CreateSolidBrush(separator_color);
    FrameRect(device_context, &rect, border_brush);
    DeleteObject(border_brush);
  }
}

bool WindowChrome::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (!IsControlId(item.CtlID)) return false;

  HBRUSH chrome_brush = CreateSolidBrush(kChromeBackground);
  FillRect(item.hDC, &item.rcItem, chrome_brush);
  DeleteObject(chrome_brush);

  const int diameter = Scale(kControlDiameter);
  const int left = item.rcItem.left +
                   ((item.rcItem.right - item.rcItem.left) - diameter) / 2;
  const int top =
      item.rcItem.top + ((item.rcItem.bottom - item.rcItem.top) - diameter) / 2;
  RECT dot{left, top, left + diameter, top + diameter};
  COLORREF color = kInactiveControlColor;
  if (active_) {
    if (item.CtlID == IDC_WINDOW_CLOSE) color = kCloseColor;
    if (item.CtlID == IDC_WINDOW_MINIMIZE) color = kMinimizeColor;
    if (item.CtlID == IDC_WINDOW_MAXIMIZE) color = kMaximizeColor;
  }
  HBRUSH dot_brush = CreateSolidBrush(color);
  HPEN outline_pen = CreatePen(PS_SOLID, 1, color);
  HGDIOBJ old_brush = SelectObject(item.hDC, dot_brush);
  HGDIOBJ old_pen = SelectObject(item.hDC, outline_pen);
  Ellipse(item.hDC, dot.left, dot.top, dot.right, dot.bottom);
  SelectObject(item.hDC, old_brush);
  SelectObject(item.hDC, old_pen);
  DeleteObject(dot_brush);
  DeleteObject(outline_pen);

  if (controls_hovered_ || (item.itemState & ODS_FOCUS) != 0) {
    const int center_x = (dot.left + dot.right) / 2;
    const int center_y = (dot.top + dot.bottom) / 2;
    const int mark_radius = std::max(2, Scale(3));
    HPEN mark_pen = CreatePen(PS_SOLID, std::max(1, Scale(1)), RGB(62, 45, 44));
    old_pen = SelectObject(item.hDC, mark_pen);
    if (item.CtlID == IDC_WINDOW_CLOSE) {
      MoveToEx(item.hDC, center_x - mark_radius, center_y - mark_radius,
               nullptr);
      LineTo(item.hDC, center_x + mark_radius + 1, center_y + mark_radius + 1);
      MoveToEx(item.hDC, center_x + mark_radius, center_y - mark_radius,
               nullptr);
      LineTo(item.hDC, center_x - mark_radius - 1, center_y + mark_radius + 1);
    } else if (item.CtlID == IDC_WINDOW_MINIMIZE) {
      MoveToEx(item.hDC, center_x - mark_radius, center_y, nullptr);
      LineTo(item.hDC, center_x + mark_radius + 1, center_y);
    } else {
      MoveToEx(item.hDC, center_x - mark_radius, center_y, nullptr);
      LineTo(item.hDC, center_x + mark_radius + 1, center_y);
      MoveToEx(item.hDC, center_x, center_y - mark_radius, nullptr);
      LineTo(item.hDC, center_x, center_y + mark_radius + 1);
    }
    SelectObject(item.hDC, old_pen);
    DeleteObject(mark_pen);
  }
  return true;
}

bool WindowChrome::EraseBackground(HDC device_context) const {
  if (window_ == nullptr) return false;
  RECT rect{};
  GetClientRect(window_, &rect);
  HBRUSH brush = CreateSolidBrush(kChromeBackground);
  FillRect(device_context, &rect, brush);
  DeleteObject(brush);
  return true;
}

LRESULT WindowChrome::HitTest(WPARAM wparam, LPARAM lparam) const {
  if (window_ == nullptr) return HTNOWHERE;
  LRESULT dwm_result = 0;
  if (DwmDefWindowProc(window_, WM_NCHITTEST, wparam, lparam, &dwm_result))
    return dwm_result;

  POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  RECT window_rect{};
  GetWindowRect(window_, &window_rect);
  const int border = Scale(kResizeBorderWidth);
  if (!IsZoomed(window_)) {
    const bool left = point.x < window_rect.left + border;
    const bool right = point.x >= window_rect.right - border;
    const bool top = point.y < window_rect.top + border;
    const bool bottom = point.y >= window_rect.bottom - border;
    if (top && left) return HTTOPLEFT;
    if (top && right) return HTTOPRIGHT;
    if (bottom && left) return HTBOTTOMLEFT;
    if (bottom && right) return HTBOTTOMRIGHT;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
    if (top) return HTTOP;
    if (bottom) return HTBOTTOM;
  }

  ScreenToClient(window_, &point);
  if (point.y < TitleBarHeight() && !IsPointInControls(point)) return HTCAPTION;
  return HTCLIENT;
}

int WindowChrome::Inset() const {
  return window_ != nullptr && IsZoomed(window_) ? 0 : Scale(1);
}

void WindowChrome::LayoutControls() {
  if (window_ == nullptr) return;
  const int control_size = Scale(kControlBoxSize);
  const int control_gap = Scale(kControlGap);
  int control_left = Scale(kControlInset);
  const int control_top = (TitleBarHeight() - control_size) / 2;
  for (HWND control : {close_button_, minimize_button_, maximize_button_}) {
    if (control != nullptr) {
      SetWindowPos(control, HWND_TOP, control_left, control_top, control_size,
                   control_size, SWP_NOACTIVATE);
    }
    control_left += control_size + control_gap;
  }
}

void WindowChrome::SetDpi(UINT dpi) {
  dpi_ = dpi == 0 ? 96U : dpi;
}

void WindowChrome::SetActive(bool active) {
  active_ = active;
  if (window_ == nullptr) return;
  InvalidateRect(window_, nullptr, FALSE);
  for (HWND control : {close_button_, minimize_button_, maximize_button_}) {
    if (control != nullptr)
      RedrawWindow(control, nullptr, nullptr, RDW_INVALIDATE);
  }
  UpdateDwmFrame();
}

void WindowChrome::TrackMouse(POINT point) {
  if (window_ == nullptr) return;
  SetControlsHovered(IsPointInControls(point));
  TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window_, 0};
  TrackMouseEvent(&tracking);
}

void WindowChrome::TrackMouseLeave() { SetControlsHovered(false); }

int WindowChrome::TitleBarHeight() const { return Scale(kTitleBarHeight); }

void WindowChrome::UpdateDwmFrame() {
  if (window_ == nullptr) return;
  const DWORD corner_preference =
      IsZoomed(window_) ? kDwmDoNotRound : kDwmRound;
  DwmSetWindowAttribute(window_, kDwmWindowCornerPreferenceAttribute,
                        &corner_preference, sizeof(corner_preference));
  const COLORREF border_color = active_ ? kActiveBorder : kInactiveBorder;
  DwmSetWindowAttribute(window_, kDwmBorderColorAttribute, &border_color,
                        sizeof(border_color));
  const MARGINS margins{1, 1, 1, 1};
  DwmExtendFrameIntoClientArea(window_, &margins);
}

LRESULT CALLBACK WindowChrome::ControlProc(HWND hwnd, UINT message,
                                           WPARAM wparam, LPARAM lparam,
                                           UINT_PTR subclass_id,
                                           DWORD_PTR reference_data) {
  auto* self = reinterpret_cast<WindowChrome*>(reference_data);
  if (message == WM_MOUSEMOVE && self != nullptr) {
    self->SetControlsHovered(true);
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&tracking);
  } else if (message == WM_MOUSELEAVE && self != nullptr) {
    POINT point{};
    GetCursorPos(&point);
    ScreenToClient(self->window_, &point);
    self->SetControlsHovered(self->IsPointInControls(point));
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, &WindowChrome::ControlProc, subclass_id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

bool WindowChrome::IsPointInControls(POINT point) const {
  if (close_button_ == nullptr || maximize_button_ == nullptr) return false;
  RECT first{};
  RECT last{};
  GetWindowRect(close_button_, &first);
  GetWindowRect(maximize_button_, &last);
  MapWindowPoints(HWND_DESKTOP, window_, reinterpret_cast<POINT*>(&first), 2);
  MapWindowPoints(HWND_DESKTOP, window_, reinterpret_cast<POINT*>(&last), 2);
  RECT controls{first.left, std::min(first.top, last.top), last.right,
                std::max(first.bottom, last.bottom)};
  return PtInRect(&controls, point) != FALSE;
}

int WindowChrome::Scale(int value) const {
  return MulDiv(value, static_cast<int>(dpi_), 96);
}

void WindowChrome::SetControlsHovered(bool hovered) {
  if (controls_hovered_ == hovered) return;
  controls_hovered_ = hovered;
  for (HWND control : {close_button_, minimize_button_, maximize_button_}) {
    if (control != nullptr)
      RedrawWindow(control, nullptr, nullptr, RDW_INVALIDATE);
  }
}

}  // namespace kelpie::windows
