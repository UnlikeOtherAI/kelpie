#include "window_chrome.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>

#include "../resources/resource.h"
#include "theme/theme.h"

namespace kelpie::windows {
namespace {

constexpr int kTitleBarHeight = 38;
constexpr int kResizeBorderWidth = 8;
constexpr int kControlBoxSize = 20;
constexpr int kControlDiameter = 14;
constexpr int kControlGap = 4;
constexpr int kControlInset = 12;
constexpr DWORD kDwmWindowCornerPreference = 33;
constexpr DWORD kDwmBorderColor = 34;
constexpr DWORD kDwmRound = 2;
constexpr DWORD kDwmDoNotRound = 1;

bool IsControlId(UINT id) {
  return id == IDC_WINDOW_CLOSE || id == IDC_WINDOW_MINIMIZE ||
         id == IDC_WINDOW_MAXIMIZE;
}

}  // namespace

void WindowChrome::Attach(HWND window, HINSTANCE instance) {
  window_ = window;
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
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW, 0, 0, 0, 0, window_,
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
  const auto colors = ui::Colors();
  HBRUSH chrome_brush = CreateSolidBrush(colors.canvas);
  FillRect(device_context, &title_rect, chrome_brush);
  DeleteObject(chrome_brush);

  const COLORREF separator_color = active_ ? colors.border : colors.muted_text;
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
  SetTextColor(device_context, colors.text);
  HFONT title_font = ui::MakeFont(window_, 13, FW_NORMAL);
  HGDIOBJ old_font = SelectObject(device_context, title_font);
  DrawTextW(
      device_context, title, -1, &text_rect,
      DT_CENTER | DT_END_ELLIPSIS | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
  SelectObject(device_context, old_font);
  DeleteObject(title_font);

  if (!IsZoomed(window_)) {
    HBRUSH border_brush = CreateSolidBrush(separator_color);
    FrameRect(device_context, &rect, border_brush);
    DeleteObject(border_brush);
  }
}

bool WindowChrome::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (!IsControlId(item.CtlID)) return false;

  const auto colors = ui::Colors();
  HBRUSH chrome_brush = CreateSolidBrush(colors.canvas);
  FillRect(item.hDC, &item.rcItem, chrome_brush);
  DeleteObject(chrome_brush);

  const int diameter = Scale(kControlDiameter);
  const int left = item.rcItem.left +
                   ((item.rcItem.right - item.rcItem.left) - diameter) / 2;
  const int top =
      item.rcItem.top + ((item.rcItem.bottom - item.rcItem.top) - diameter) / 2;
  RECT dot{left, top, left + diameter, top + diameter};
  COLORREF color = ui::HighContrast() ? colors.muted_text : RGB(184, 184, 184);
  if (active_) {
    if (item.CtlID == IDC_WINDOW_CLOSE) color = ui::HighContrast() ? colors.focus : RGB(255, 95, 87);
    if (item.CtlID == IDC_WINDOW_MINIMIZE) color = ui::HighContrast() ? colors.focus : RGB(254, 188, 46);
    if (item.CtlID == IDC_WINDOW_MAXIMIZE) color = ui::HighContrast() ? colors.focus : RGB(40, 200, 64);
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
    HPEN mark_pen = CreatePen(PS_SOLID, std::max(1, Scale(1)),
                              ui::HighContrast() ? colors.text : RGB(62, 45, 44));
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
  HBRUSH brush = CreateSolidBrush(ui::Colors().canvas);
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
  return window_ != nullptr && IsZoomed(window_) ? 0 : 1;
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
  DwmSetWindowAttribute(
      window_, static_cast<DWMWINDOWATTRIBUTE>(kDwmWindowCornerPreference),
      &corner_preference, sizeof(corner_preference));
  const auto colors = ui::Colors();
  const COLORREF border_color = active_ ? colors.border : colors.muted_text;
  DwmSetWindowAttribute(window_,
                        static_cast<DWMWINDOWATTRIBUTE>(kDwmBorderColor),
                        &border_color, sizeof(border_color));
  // The title bar and system border are drawn by DWM, not by this class, so
  // they only follow the app theme once the dark-mode attribute is applied.
  ui::ApplyWindowAppearance(window_);
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
  return ui::Dip(window_, value);
}

std::vector<HWND> WindowChrome::FocusableControls() const {
  std::vector<HWND> controls;
  for (HWND control : {close_button_, minimize_button_, maximize_button_}) {
    if (control != nullptr && IsWindowVisible(control) && IsWindowEnabled(control)) controls.push_back(control);
  }
  return controls;
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
