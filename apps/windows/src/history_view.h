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

class HistoryView {
 public:
  bool EnsureCreated(HINSTANCE instance, HWND owner);
  void ToggleVisible();
  void UpdateFromJson(const std::string& history_json);

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void CreateListView();
  void Resize();
  void Populate();

  HINSTANCE instance_ = nullptr;
  HWND owner_ = nullptr;
  HWND hwnd_ = nullptr;
  HWND list_view_ = nullptr;
  std::string history_json_ = "[]";
};

}  // namespace kelpie::windows
