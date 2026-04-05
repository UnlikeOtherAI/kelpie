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

class ToastView {
 public:
  bool Create(HWND parent, HINSTANCE instance);
  void Resize(const RECT& parent_bounds);
  void ShowMessage(const std::wstring& message);
  void Hide();

 private:
  HWND hwnd_ = nullptr;
  HWND label_ = nullptr;
};

}  // namespace kelpie::windows
