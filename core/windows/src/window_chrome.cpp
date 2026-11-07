#include "window_chrome.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>

#include "../resources/resource.h"
#include "maximized_frame.h"
#include "theme/theme.h"

namespace kelpie::windows {
namespace {

constexpr int kTitleBarHeight = 52;
constexpr int kResizeBorderWidth = 8;
constexpr int kControlBoxSize = 50;
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
  ui::FillSolid(device_context, title_rect, palette_.caption);
  if (!IsZoomed(window_)) {
    HBRUSH border_brush = CreateSolidBrush(palette_.line);
    FrameRect(device_context, &rect, border_brush);
    DeleteObject(border_brush);
}
}

bool WindowChrome::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (!IsControlId(item.CtlID)) return false;
  const bool hovered = item.hwndItem == hovered_control_;
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  const bool close = item.CtlID == IDC_WINDOW_CLOSE;
  const COLORREF fill = close && (hovered || pressed) ? RGB(196, 43, 28)
      : (hovered || pressed) ? ui::Blend(palette_.caption_text, palette_.caption, 0.08) : palette_.caption;
  ui::FillSolid(item.hDC, item.rcItem, fill);
  const COLORREF ink = close && (hovered || pressed) ? RGB(255,255,255) : palette_.caption_text;
  const int x = (item.rcItem.left + item.rcItem.right) / 2;
  const int y = (item.rcItem.top + item.rcItem.bottom) / 2;
  const int r = Scale(5);
  HPEN pen = CreatePen(PS_SOLID, std::max(1, Scale(1)), ink);
  const auto old = SelectObject(item.hDC, pen);
  const auto brush = SelectObject(item.hDC, GetStockObject(NULL_BRUSH));
  if (close) {
    MoveToEx(item.hDC, x-r, y-r, nullptr); LineTo(item.hDC, x+r+1, y+r+1);
    MoveToEx(item.hDC, x+r, y-r, nullptr); LineTo(item.hDC, x-r-1, y+r+1);
  } else if (item.CtlID == IDC_WINDOW_MINIMIZE) {
    MoveToEx(item.hDC, x-r, y, nullptr); LineTo(item.hDC, x+r+1, y);
  } else if (IsZoomed(window_)) {
    Rectangle(item.hDC, x-r+2, y-r, x+r+1, y+r-1);
    ui::FillSolid(item.hDC, RECT{x-r,y-r+2,x+r-1,y+r+1}, fill);
    Rectangle(item.hDC, x-r, y-r+2, x+r-1, y+r+1);
  } else {
    Rectangle(item.hDC, x-r, y-r, x+r+1, y+r+1);
  }
  SelectObject(item.hDC, brush);
  SelectObject(item.hDC, old);
  DeleteObject(pen);
  if ((item.itemState & ODS_FOCUS) != 0) DrawFocusRect(item.hDC, &item.rcItem);
  return true;
}

bool WindowChrome::EraseBackground(HDC device_context) const {
  if (window_ == nullptr) return false;
  RECT rect{};
  GetClientRect(window_, &rect);
  HBRUSH brush = CreateSolidBrush(palette_.bar);
  FillRect(device_context, &rect, brush);
  DeleteObject(brush);
  return true;
}

LRESULT WindowChrome::CalcClientArea(NCCALCSIZE_PARAMS* params) const {
  // Restored, the whole window is client area: Draw paints the border and
  // HitTest supplies the resize edges, and rgrc[0] already is that rect.
  // Maximized, the frame Windows hangs off the monitor has to come back off.
  if (window_ != nullptr && IsZoomed(window_)) {
    RECT& proposed = params->rgrc[0];
    const HMONITOR monitor = MonitorFromRect(&proposed, MONITOR_DEFAULTTONEAREST);
    proposed = MaximizedClientRect(proposed, MaximizedFrameThickness(window_),
                                   AutoHideAppbarEdges(monitor));
  }
  return 0;
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
  RECT bounds{};
  GetClientRect(window_, &bounds);
  int control_left = bounds.right - Inset() - control_size * 3;
  const int control_top = Inset();
  for (HWND control : {minimize_button_, maximize_button_, close_button_}) {
    if (control != nullptr) {
      SetWindowPos(control, HWND_TOP, control_left, control_top, control_size,
                   TitleBarHeight() - control_top, SWP_NOACTIVATE);
    }
    control_left += control_size;
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
  if (message == WM_NCHITTEST && self != nullptr) {
    const auto hit = self->HitTest(wparam, lparam);
    if (hit >= HTLEFT && hit <= HTBOTTOMRIGHT) return HTTRANSPARENT;
  }
  if (message == WM_MOUSEMOVE && self != nullptr) {
    self->hovered_control_ = hwnd;
    self->SetControlsHovered(true);
    InvalidateRect(hwnd, nullptr, FALSE);
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&tracking);
  } else if (message == WM_MOUSELEAVE && self != nullptr) {
    self->hovered_control_ = nullptr;
    InvalidateRect(hwnd, nullptr, FALSE);
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
  GetWindowRect(minimize_button_, &first);
  GetWindowRect(close_button_, &last);
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
