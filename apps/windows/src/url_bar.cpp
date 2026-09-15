#include "url_bar.h"

#include <algorithm>

#include "../resources/resource.h"
#include "url_completion.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {

std::wstring ReadWindowText(HWND hwnd) {
  const int length = GetWindowTextLengthW(hwnd);
  if (length <= 0) return {};
  std::wstring value(static_cast<std::size_t>(length) + 1, L'\0');
  const int copied = GetWindowTextW(hwnd, value.data(), static_cast<int>(value.size()));
  value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0);
  return value;
}

}  // namespace

bool UrlBar::Create(HWND parent, HINSTANCE instance, const RECT& bounds, UrlBarDelegate* delegate) {
  parent_ = parent;
  delegate_ = delegate;
  back_button_ = CreateWindowExW(0, L"BUTTON", L"<", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                 0, 0, kButtonWidth, kControlHeight, parent, reinterpret_cast<HMENU>(IDC_BACK_BUTTON), instance, nullptr);
  forward_button_ = CreateWindowExW(0, L"BUTTON", L">", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                    0, 0, kButtonWidth, kControlHeight, parent, reinterpret_cast<HMENU>(IDC_FORWARD_BUTTON), instance, nullptr);
  reload_button_ = CreateWindowExW(0, L"BUTTON", L"Reload", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                   0, 0, 52, kControlHeight, parent, reinterpret_cast<HMENU>(IDC_RELOAD_BUTTON), instance, nullptr);
  settings_button_ = CreateWindowExW(0, L"BUTTON", L"Menu", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                     0, 0, 56, kControlHeight, parent, reinterpret_cast<HMENU>(IDC_SETTINGS_BUTTON), instance, nullptr);
  url_edit_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                              0, 0, 200, kControlHeight, parent, reinterpret_cast<HMENU>(IDC_URL_EDIT), instance, nullptr);
  if (!back_button_ || !forward_button_ || !reload_button_ || !settings_button_ || !url_edit_) return false;
  SetWindowLongPtrW(url_edit_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
  original_edit_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(url_edit_, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&UrlBar::EditProc)));
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
  SetWindowPos(reload_button_, nullptr, left, top, 52, kControlHeight, SWP_NOZORDER);
  const int settings_width = 56;
  const int url_left = left + 52 + kGap;
  const int url_right = bounds.right - settings_width - 16;
  SetWindowPos(url_edit_, nullptr, url_left, top, std::max(120, url_right - url_left), kControlHeight, SWP_NOZORDER);
  SetWindowPos(settings_button_, nullptr, bounds.right - settings_width - 8, top, settings_width, kControlHeight, SWP_NOZORDER);
}

void UrlBar::SetUrl(const std::wstring& url, bool force) {
  if (url_edit_ == nullptr || (!force && GetFocus() == url_edit_)) return;
  setting_url_ = true;
  completion_active_ = false;
  insertion_at_end_ = false;
  completion_prefix_.clear();
  SetWindowTextW(url_edit_, url.c_str());
  setting_url_ = false;
}

void UrlBar::SetNavigationState(bool can_go_back, bool can_go_forward, bool is_loading) {
  EnableWindow(back_button_, can_go_back ? TRUE : FALSE);
  EnableWindow(forward_button_, can_go_forward ? TRUE : FALSE);
  SetWindowTextW(reload_button_, is_loading ? L"Stop" : L"Reload");
}

void UrlBar::Focus() {
  completion_active_ = false;
  SetFocus(url_edit_);
  SendMessageW(url_edit_, EM_SETSEL, 0, -1);
}

bool UrlBar::HandleCommand(WORD control_id, WORD notification_code) {
  if (control_id != IDC_URL_EDIT || notification_code != EN_CHANGE || setting_url_) return false;
  CompleteAfterInsertion();
  return true;
}

LRESULT CALLBACK UrlBar::EditProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<UrlBar*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self == nullptr) return DefWindowProcW(hwnd, message, wparam, lparam);
  if (message == WM_CHAR) {
    const std::wstring before = ReadWindowText(hwnd);
    DWORD start = 0;
    DWORD end = 0;
    SendMessageW(hwnd, EM_GETSEL, reinterpret_cast<WPARAM>(&start), reinterpret_cast<LPARAM>(&end));
    self->insertion_at_end_ = completion::IsTextInsertionAtEnd(
        self->ime_composing_, before.size(), start, end, static_cast<wchar_t>(wparam));
    self->completion_active_ = false;
  } else if (message == WM_PASTE || message == WM_CUT || message == WM_CLEAR || message == WM_UNDO || message == WM_IME_STARTCOMPOSITION) {
    self->insertion_at_end_ = false;
    self->completion_active_ = false;
    if (message == WM_IME_STARTCOMPOSITION) self->ime_composing_ = true;
  } else if (message == WM_IME_ENDCOMPOSITION) {
    self->ime_composing_ = false;
  } else if (message == WM_KEYDOWN) {
    if (wparam == VK_ESCAPE && self->completion_active_) {
      self->RejectCompletion();
      return 0;
    }
    if (wparam == VK_RETURN) {
      if (self->completion_active_) SendMessageW(hwnd, EM_SETSEL, -1, -1);
      self->completion_active_ = false;
      self->SubmitCurrentUrl();
      return 0;
    }
    self->completion_active_ = false;
    if (wparam == VK_BACK || wparam == VK_DELETE) {
      self->insertion_at_end_ = false;
    }
  } else if (message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN || message == WM_MOUSEWHEEL) {
    self->completion_active_ = false;
  }
  return CallWindowProcW(self->original_edit_proc_, hwnd, message, wparam, lparam);
}

void UrlBar::CompleteAfterInsertion() {
  if (!insertion_at_end_) return;
  insertion_at_end_ = false;
  const std::wstring typed = ReadWindowText(url_edit_);
  const auto candidate = delegate_ == nullptr ? std::nullopt : delegate_->BestUrlCompletion(typed);
  if (!candidate || !completion::IsStrictSuffix(typed, *candidate)) return;
  setting_url_ = true;
  SetWindowTextW(url_edit_, candidate->c_str());
  SendMessageW(url_edit_, EM_SETSEL, static_cast<WPARAM>(typed.size()), static_cast<LPARAM>(candidate->size()));
  setting_url_ = false;
  completion_prefix_ = typed;
  completion_active_ = true;
}

void UrlBar::RejectCompletion() {
  setting_url_ = true;
  SetWindowTextW(url_edit_, completion_prefix_.c_str());
  SendMessageW(url_edit_, EM_SETSEL, -1, -1);
  setting_url_ = false;
  completion_active_ = false;
}

void UrlBar::SubmitCurrentUrl() {
  if (delegate_ == nullptr || url_edit_ == nullptr) return;
  const auto url = utf::WideToUtf8(ReadWindowText(url_edit_));
  if (url && !url->empty()) delegate_->OnNavigateRequested(*url);
}

}  // namespace kelpie::windows
