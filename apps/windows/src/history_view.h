#pragma once

#include <string>
#include <functional>

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
  void SetNavigateCallback(std::function<void(const std::string&)> callback);

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void CreateListView();
  void Resize();
  void Populate();
  void RefreshFont();

  HINSTANCE instance_ = nullptr;
  HWND owner_ = nullptr;
  HWND hwnd_ = nullptr;
  HWND list_view_ = nullptr;
  HFONT list_font_ = nullptr;
  std::string history_json_ = "[]";
  std::function<void(const std::string&)> on_navigate_;
};

}  // namespace kelpie::windows
