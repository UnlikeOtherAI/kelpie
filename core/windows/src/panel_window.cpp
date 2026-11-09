#include "panel_window.h"

#include "theme/theme.h"

namespace kelpie::windows {

void PanelWindow::Toggle(HINSTANCE instance, HWND owner) {
  if (hwnd_ == nullptr && !Create(instance, owner)) return;
  if (IsShowing()) {
    Hide();
    return;
  }
  ShowWindow(hwnd_, SW_SHOW);
  SetForegroundWindow(hwnd_);
  OnShown();
}

void PanelWindow::Hide() {
  if (hwnd_ == nullptr) return;
  ShowWindow(hwnd_, SW_HIDE);
  // Hiding an owned window can leave activation nowhere; give it back to the
  // browser the person came from.
  if (owner_ != nullptr && IsWindowVisible(owner_)) SetForegroundWindow(owner_);
}

bool PanelWindow::IsShowing() const { return hwnd_ != nullptr && IsWindowVisible(hwnd_) != FALSE; }

bool PanelWindow::Create(HINSTANCE instance, HWND owner) {
  instance_ = instance;
  owner_ = owner;
  const Spec spec = Describe();
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = &PanelWindow::WindowProc;
  window_class.hInstance = instance_;
  window_class.lpszClassName = spec.class_name;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);
  // Created directly at its final rectangle, so it is born on the browser's
  // monitor at that monitor's DPI rather than cascaded from the screen corner.
  const RECT frame = ui::OwnedWindowRect(owner_, spec.size_dip, kStyle, kExStyle);
  CreateWindowExW(kExStyle, spec.class_name, spec.title, kStyle, frame.left, frame.top,
                  frame.right - frame.left, frame.bottom - frame.top, owner_, nullptr, instance_,
                  this);
  return hwnd_ != nullptr;
}

void PanelWindow::RefreshFont() {
  HFONT next = ui::MakeFont(hwnd_, 13, FW_NORMAL);
  if (next == nullptr) return;
  if (font_ != nullptr) DeleteObject(font_);
  font_ = next;
}

LRESULT CALLBACK PanelWindow::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<PanelWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<PanelWindow*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  }
  return self != nullptr ? self->HandleMessage(message, wparam, lparam)
                         : DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT PanelWindow::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  const HWND window = hwnd_;
  LRESULT handled = 0;
  if (message != WM_CREATE && message != WM_NCCREATE &&
      HandlePanelMessage(message, wparam, lparam, &handled)) {
    return handled;
  }
  switch (message) {
    case WM_CREATE:
      RefreshFont();
      ui::ApplyWindowAppearance(hwnd_);
      CreateControls();
      return 0;
    case WM_SIZE: {
      RECT client{};
      GetClientRect(hwnd_, &client);
      Layout(client);
      return 0;
    }
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const SIZE minimum = ui::OuterSizeForClient(hwnd_, Describe().min_size_dip, kStyle, kExStyle);
      info->ptMinTrackSize = {minimum.cx, minimum.cy};
      return 0;
    }
    case ui::kDpiChangedMessage:
      RefreshFont();
      ApplyTheme();
      ui::ApplySuggestedDpiRect(hwnd_, lparam);
      return 0;
    case WM_SETTINGCHANGE:
    case WM_THEMECHANGED:
    case WM_SYSCOLORCHANGE:
      if (ui::IsAppearanceChange(message, lparam)) {
        ui::InvalidateAppearanceCache();
        ui::ApplyWindowAppearance(hwnd_);
        ApplyTheme();
        RedrawWindow(hwnd_, nullptr, nullptr, RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN);
      }
      break;
    case WM_ERASEBKGND: {
      RECT client{};
      GetClientRect(hwnd_, &client);
      ui::FillSolid(reinterpret_cast<HDC>(wparam), client, ui::Colors().canvas);
      return TRUE;
    }
    case WM_COMMAND:
      // IsDialogMessage turns Escape into IDCANCEL, from any control.
      if (LOWORD(wparam) == IDCANCEL) {
        Hide();
        return 0;
      }
      break;
    case WM_CLOSE:
      // Destroying would leave the toolbar holding a dead handle; hide instead.
      Hide();
      return 0;
    case WM_DESTROY:
      if (font_ != nullptr) DeleteObject(font_);
      font_ = nullptr;
      return 0;
    case WM_NCDESTROY:
      hwnd_ = nullptr;
      break;
    default:
      break;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace kelpie::windows
