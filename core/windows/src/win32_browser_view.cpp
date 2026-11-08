#include "win32_browser_view.h"
#include "windows_utf.h"

#include <string>
#include <cwchar>

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
  hwnd_ = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
                          bounds.left, bounds.top, bounds.right - bounds.left,
                          bounds.bottom - bounds.top, parent, nullptr, instance, nullptr);
  if (hwnd_ == nullptr) {
    return false;
  }

  fallback_label_ = CreateWindowExW(0, L"STATIC", L"Starting browser…",
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
  for (HWND child = GetWindow(hwnd_, GW_CHILD); child != nullptr; child = GetWindow(child, GW_HWNDNEXT)) {
    SetWindowPos(child, nullptr, 0, 0, bounds.right - bounds.left, bounds.bottom - bounds.top, SWP_NOZORDER);
  }
}

void Win32BrowserView::Focus() {
  if (hwnd_ != nullptr) {
    HWND focus = hwnd_;
    for (HWND child = GetWindow(hwnd_, GW_CHILD); child != nullptr; child = GetWindow(child, GW_HWNDNEXT)) {
      if (IsWindowVisible(child)) { focus = child; break; }
    }
    SetFocus(focus);
  }
}

bool Win32BrowserView::HasNativeBrowser() const {
  if (hwnd_ == nullptr || !IsWindow(hwnd_)) {
    return false;
  }
  RECT container{};
  if (!GetClientRect(hwnd_, &container) || container.right <= container.left || container.bottom <= container.top) {
    return false;
  }
  for (HWND child = GetWindow(hwnd_, GW_CHILD); child != nullptr; child = GetWindow(child, GW_HWNDNEXT)) {
    if (child == fallback_label_ || !IsWindowVisible(child)) {
      continue;
    }
    wchar_t class_name[64]{};
    GetClassNameW(child, class_name, static_cast<int>(std::size(class_name)));
    if (std::wcsncmp(class_name, L"Chrome_WidgetWin", 16) != 0) {
      continue;
    }
    RECT bounds{};
    if (GetWindowRect(child, &bounds) && bounds.right > bounds.left && bounds.bottom > bounds.top) {
      return true;
    }
  }
  return false;
}

BrowserState Win32BrowserView::state() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return state_;
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
  if (fallback_label_ == nullptr) return;
  ShowWindow(fallback_label_, visible ? SW_SHOW : SW_HIDE);
  // Hiding the startup label must invalidate the container. Its child-clipping
  // style then leaves repaint ownership with the attached CEF child.
  if (hwnd_ != nullptr) {
    RedrawWindow(hwnd_, nullptr, nullptr, RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN);
  }
}

void Win32BrowserView::UpdateFallbackText(const std::wstring& message) const {
  if (fallback_label_ != nullptr) {
    SetWindowTextW(fallback_label_, message.c_str());
  }
}

}  // namespace kelpie::windows
