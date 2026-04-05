#include "url_bar.h"

#include <algorithm>
#include <string>

#include "../resources/resource.h"

namespace kelpie::windows {
namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), '\0');
  if (size > 1) {
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1, nullptr, nullptr);
  }
  return output;
}

}  // namespace

bool UrlBar::Create(HWND parent, HINSTANCE instance, const RECT& bounds, UrlBarDelegate* delegate) {
  parent_ = parent;
  delegate_ = delegate;

  back_button_ = CreateWindowExW(0, L"BUTTON", L"<", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                 0, 0, kButtonWidth, kControlHeight, parent, reinterpret_cast<HMENU>(IDC_BACK_BUTTON),
                                 instance, nullptr);
  forward_button_ = CreateWindowExW(0, L"BUTTON", L">", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                    0, 0, kButtonWidth, kControlHeight, parent,
                                    reinterpret_cast<HMENU>(IDC_FORWARD_BUTTON), instance, nullptr);
  reload_button_ = CreateWindowExW(0, L"BUTTON", L"R", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                   0, 0, kButtonWidth, kControlHeight, parent,
                                   reinterpret_cast<HMENU>(IDC_RELOAD_BUTTON), instance, nullptr);
  settings_button_ = CreateWindowExW(0, L"BUTTON", L"Menu", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                     0, 0, 56, kControlHeight, parent,
                                     reinterpret_cast<HMENU>(IDC_SETTINGS_BUTTON), instance, nullptr);
  url_edit_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                              0, 0, 200, kControlHeight, parent, reinterpret_cast<HMENU>(IDC_URL_EDIT),
                              instance, nullptr);
  if (!back_button_ || !forward_button_ || !reload_button_ || !settings_button_ || !url_edit_) {
    return false;
  }

  SetWindowLongPtrW(url_edit_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
  original_edit_proc_ = reinterpret_cast<WNDPROC>(
      SetWindowLongPtrW(url_edit_, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&UrlBar::EditProc)));
  Resize(bounds);
  return true;
}

void UrlBar::Resize(const RECT& bounds) {
  const int top = bounds.top + 4;
  int left = bounds.left + 8;

  SetWindowPos(back_button_, nullptr, left, top, kButtonWidth, kControlHeight, SWP_NOZORDER);
  left += kButtonWidth + kGap;
  SetWindowPos(forward_button_, nullptr, left, top, kButtonWidth, kControlHeight, SWP_NOZORDER);
  left += kButtonWidth + kGap;
  SetWindowPos(reload_button_, nullptr, left, top, kButtonWidth, kControlHeight, SWP_NOZORDER);

  const int settings_width = 56;
  const int url_right = bounds.right - settings_width - 16;
  const int url_left = left + kButtonWidth + kGap;
  SetWindowPos(url_edit_, nullptr, url_left, top, std::max(120, url_right - url_left), kControlHeight,
               SWP_NOZORDER);
  SetWindowPos(settings_button_, nullptr, bounds.right - settings_width - 8, top, settings_width,
               kControlHeight, SWP_NOZORDER);
}

void UrlBar::SetUrl(const std::wstring& url) {
  if (url_edit_ != nullptr) {
    SetWindowTextW(url_edit_, url.c_str());
  }
}

void UrlBar::SetNavigationState(bool can_go_back, bool can_go_forward, bool is_loading) {
  EnableWindow(back_button_, can_go_back ? TRUE : FALSE);
  EnableWindow(forward_button_, can_go_forward ? TRUE : FALSE);
  SetWindowTextW(reload_button_, is_loading ? L"Stop" : L"R");
}

LRESULT CALLBACK UrlBar::EditProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<UrlBar*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr && message == WM_KEYDOWN && wparam == VK_RETURN) {
    self->SubmitCurrentUrl();
    return 0;
  }
  return CallWindowProcW(self != nullptr ? self->original_edit_proc_ : DefWindowProcW,
                         hwnd, message, wparam, lparam);
}

void UrlBar::SubmitCurrentUrl() {
  if (delegate_ == nullptr || url_edit_ == nullptr) {
    return;
  }
  const int length = GetWindowTextLengthW(url_edit_);
  std::wstring buffer(static_cast<std::size_t>(length), L'\0');
  GetWindowTextW(url_edit_, buffer.data(), length + 1);
  delegate_->OnNavigateRequested(WideToUtf8(buffer));
}

}  // namespace kelpie::windows
