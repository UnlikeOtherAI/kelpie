#pragma once

#include <string>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows {

class UrlBarDelegate {
 public:
  virtual ~UrlBarDelegate() = default;
  virtual void OnNavigateRequested(const std::string& url) = 0;
  virtual void OnBackRequested() = 0;
  virtual void OnForwardRequested() = 0;
  virtual void OnReloadRequested() = 0;
  virtual void OnOpenSettingsRequested() = 0;
};

class UrlBar {
 public:
  bool Create(HWND parent, HINSTANCE instance, const RECT& bounds, UrlBarDelegate* delegate);
  void Resize(const RECT& bounds);
  void SetUrl(const std::wstring& url);
  void SetNavigationState(bool can_go_back, bool can_go_forward, bool is_loading);
  int Height() const { return kControlHeight + 8; }

 private:
  static LRESULT CALLBACK EditProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void SubmitCurrentUrl();

  static constexpr int kControlHeight = 32;
  static constexpr int kButtonWidth = 32;
  static constexpr int kGap = 8;

  HWND parent_ = nullptr;
  UrlBarDelegate* delegate_ = nullptr;
  HWND back_button_ = nullptr;
  HWND forward_button_ = nullptr;
  HWND reload_button_ = nullptr;
  HWND settings_button_ = nullptr;
  HWND url_edit_ = nullptr;
  WNDPROC original_edit_proc_ = nullptr;
};

}  // namespace kelpie::windows
