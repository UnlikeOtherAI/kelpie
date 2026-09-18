#include "toast_view.h"

#include <algorithm>

#include "ui_theme.h"

namespace kelpie::windows {
namespace {
constexpr wchar_t kToastClass[] = L"KelpieToast";
}

bool ToastView::Create(HWND parent, HINSTANCE instance) {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = &ToastView::WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kToastClass;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);
  hwnd_ = CreateWindowExW(WS_EX_LAYERED | WS_EX_NOACTIVATE, kToastClass, L"", WS_CHILD,
                          0, 0, 0, 0, parent, nullptr, instance, this);
  if (hwnd_ != nullptr) SetLayeredWindowAttributes(hwnd_, 0, static_cast<BYTE>(248), LWA_ALPHA);
  return hwnd_ != nullptr;
}

void ToastView::Resize(const RECT& parent_bounds) {
  if (hwnd_ == nullptr) return;
  const int available = static_cast<int>(parent_bounds.right - parent_bounds.left) - ui::Dip(hwnd_, 40);
  const int width = std::min(ui::Dip(hwnd_, 420), std::max(ui::Dip(hwnd_, 240), available));
  const int height = ui::Dip(hwnd_, 52);
  const int left = std::max(ui::Dip(hwnd_, 20), static_cast<int>((parent_bounds.right - parent_bounds.left - width) / 2));
  const int top = std::max(ui::Dip(hwnd_, 20), static_cast<int>(parent_bounds.bottom - height - ui::Dip(hwnd_, 28)));
  SetWindowPos(hwnd_, HWND_TOP, left, top, width, height, SWP_NOACTIVATE);
}

void ToastView::ShowMessage(const std::wstring& message) {
  if (hwnd_ == nullptr) return;
  message_ = message;
  InvalidateRect(hwnd_, nullptr, FALSE);
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
}

void ToastView::Hide() { if (hwnd_ != nullptr) ShowWindow(hwnd_, SW_HIDE); }

LRESULT CALLBACK ToastView::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<ToastView*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<ToastView*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self != nullptr && message == WM_PAINT) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(hwnd, &paint);
    self->Paint(dc);
    EndPaint(hwnd, &paint);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void ToastView::Paint(HDC device_context) const {
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  const auto colors = ui::Colors();
  ui::PaintRounded(device_context, rect, colors.surface, colors.border, ui::Dip(hwnd_, 16));
  RECT icon{rect.left + ui::Dip(hwnd_, 14), rect.top, rect.left + ui::Dip(hwnd_, 38), rect.bottom};
  ui::DrawGlyph(device_context, hwnd_, icon, L'●', colors.accent, 12);
  RECT text{rect.left + ui::Dip(hwnd_, 44), rect.top + ui::Dip(hwnd_, 8), rect.right - ui::Dip(hwnd_, 14), rect.bottom - ui::Dip(hwnd_, 8)};
  HFONT font = ui::MakeFont(hwnd_, 13, FW_MEDIUM);
  HGDIOBJ old = SelectObject(device_context, font);
  SetBkMode(device_context, TRANSPARENT);
  SetTextColor(device_context, colors.text);
  DrawTextW(device_context, message_.c_str(), -1, &text, DT_LEFT | DT_VCENTER | DT_WORDBREAK | DT_END_ELLIPSIS);
  SelectObject(device_context, old);
  DeleteObject(font);
}

}  // namespace kelpie::windows
