#pragma once

#include <mutex>
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>


namespace kelpie::windows {

struct BrowserState {
  std::string url;
  std::string title;
  bool is_loading = false;
  bool can_go_back = false;
  bool can_go_forward = false;
};

class BrowserStateObserver {
 public:
  virtual ~BrowserStateObserver() = default;
  virtual void OnBrowserStateChanged(const BrowserState& state) = 0;
};

class Win32BrowserView final {
 public:
  Win32BrowserView();
  ~Win32BrowserView();

  bool Create(HWND parent, HINSTANCE instance, const RECT& bounds, BrowserStateObserver* observer);
  void Destroy();
  void Resize(const RECT& bounds);
  void Focus();
  HWND hwnd() const { return hwnd_; }
  BrowserState state() const;
  bool HasNativeBrowser() const;
  void UpdateState(BrowserState state);
  void UpdateFallbackText(const std::wstring& message) const;
  void ShowFallback(bool visible) const;


 private:
  HWND hwnd_ = nullptr;
  HWND fallback_label_ = nullptr;
  BrowserStateObserver* observer_ = nullptr;
  mutable std::mutex mutex_;
  BrowserState state_;

#if defined(HAS_CEF)
  void* client_bridge_ = nullptr;
#endif
};

}  // namespace kelpie::windows
