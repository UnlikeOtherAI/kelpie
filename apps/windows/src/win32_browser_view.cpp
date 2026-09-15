#include "win32_browser_view.h"
#include "windows_utf.h"

#include <string>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>


namespace kelpie::windows {
namespace {


}  // namespace

Win32BrowserView::Win32BrowserView() = default;

Win32BrowserView::~Win32BrowserView() {
  Destroy();
}

bool Win32BrowserView::Create(HWND parent, HINSTANCE instance, const RECT& bounds,
                              BrowserStateObserver* observer) {
  observer_ = observer;
  hwnd_ = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE,
                          bounds.left, bounds.top, bounds.right - bounds.left,
                          bounds.bottom - bounds.top, parent, nullptr, instance, nullptr);
  if (hwnd_ == nullptr) {
    return false;
  }

  fallback_label_ = CreateWindowExW(0, L"STATIC", L"Chromium runtime unavailable",
                                    WS_CHILD | WS_VISIBLE | SS_CENTER,
                                    0, 0, bounds.right - bounds.left, bounds.bottom - bounds.top,
                                    hwnd_, nullptr, instance, nullptr);

  return true;
}

void Win32BrowserView::Destroy() {
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void Win32BrowserView::Resize(const RECT& bounds) {
  if (hwnd_ == nullptr) {
    return;
  }
  SetWindowPos(hwnd_, nullptr, bounds.left, bounds.top, bounds.right - bounds.left,
               bounds.bottom - bounds.top, SWP_NOZORDER);
  if (fallback_label_ != nullptr) {
    SetWindowPos(fallback_label_, nullptr, 0, 0, bounds.right - bounds.left, bounds.bottom - bounds.top,
                 SWP_NOZORDER);
  }
}

void Win32BrowserView::Focus() {
  if (hwnd_ != nullptr) {
    SetFocus(hwnd_);
  }
}

BrowserState Win32BrowserView::state() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return state_;
}

bool Win32BrowserView::HasNativeBrowser() const { return false; }

std::string Win32BrowserView::EvaluateJs(const std::string&) {
  return {};
}

std::vector<std::uint8_t> Win32BrowserView::TakeSnapshot() {
  return {};
}

void Win32BrowserView::LoadUrl(const std::string& url) {
  BrowserState next = state();
  next.url = url;
  next.title = url;
  next.is_loading = false;
  UpdateState(next);
  UpdateFallbackText(utf::Utf8ToWideDisplay(url));
}

std::string Win32BrowserView::CurrentUrl() const {
  return state().url;
}

std::string Win32BrowserView::CurrentTitle() const {
  return state().title;
}

bool Win32BrowserView::IsLoading() const {
  return state().is_loading;
}

bool Win32BrowserView::CanGoBack() const {
  return state().can_go_back;
}

bool Win32BrowserView::CanGoForward() const {
  return state().can_go_forward;
}

void Win32BrowserView::GoBack() {
}

void Win32BrowserView::GoForward() {
}

void Win32BrowserView::Reload() {
}

void Win32BrowserView::UpdateState(BrowserState state) {
  BrowserState snapshot;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = std::move(state);
    snapshot = state_;
  }
  if (observer_ != nullptr) {
    observer_->OnBrowserStateChanged(snapshot);
  }
}

void Win32BrowserView::ShowFallback(bool visible) const {
  if (fallback_label_ != nullptr) {
    ShowWindow(fallback_label_, visible ? SW_SHOW : SW_HIDE);
  }
}

void Win32BrowserView::UpdateFallbackText(const std::wstring& message) const {
  if (fallback_label_ != nullptr) {
    SetWindowTextW(fallback_label_, message.c_str());
  }
}

}  // namespace kelpie::windows
