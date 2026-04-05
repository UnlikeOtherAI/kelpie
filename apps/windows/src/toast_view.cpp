#include "toast_view.h"

#include <algorithm>

#include "../resources/resource.h"

namespace kelpie::windows {

bool ToastView::Create(HWND parent, HINSTANCE instance) {
  hwnd_ = CreateWindowExW(WS_EX_LAYERED, L"STATIC", L"", WS_CHILD | SS_CENTER,
                          0, 0, 240, 40, parent, nullptr, instance, nullptr);
  label_ = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_CENTER,
                           0, 0, 240, 40, hwnd_, reinterpret_cast<HMENU>(IDC_TOAST_LABEL), instance,
                           nullptr);
  if (!hwnd_ || !label_) {
    return false;
  }

  SetLayeredWindowAttributes(hwnd_, 0, static_cast<BYTE>(220), LWA_ALPHA);
  ShowWindow(hwnd_, SW_HIDE);
  return true;
}

void ToastView::Resize(const RECT& parent_bounds) {
  if (hwnd_ == nullptr) {
    return;
  }
  const int width = 320;
  const int height = 40;
  const int left = std::max(16, static_cast<int>((parent_bounds.right - width) / 2));
  const int top = std::max(16, static_cast<int>(parent_bounds.bottom - height - 24));
  SetWindowPos(hwnd_, HWND_TOP, left, top, width, height, SWP_NOACTIVATE);
  SetWindowPos(label_, nullptr, 0, 0, width, height, SWP_NOZORDER);
}

void ToastView::ShowMessage(const std::wstring& message) {
  if (label_ == nullptr || hwnd_ == nullptr) {
    return;
  }
  SetWindowTextW(label_, message.c_str());
  ShowWindow(hwnd_, SW_SHOW);
}

void ToastView::Hide() {
  if (hwnd_ != nullptr) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

}  // namespace kelpie::windows
