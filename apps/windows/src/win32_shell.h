#pragma once

#include <string>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "bookmarks_view.h"
#include "history_view.h"
#include "network_inspector.h"
#include "settings_view.h"
#include "toast_view.h"
#include "url_bar.h"
#include "win32_browser_view.h"

namespace kelpie::windows {

class ShellDelegate : public UrlBarDelegate {
 public:
  ~ShellDelegate() override = default;
  virtual std::string GetBookmarksJson() const = 0;
  virtual std::string GetHistoryJson() const = 0;
  virtual std::string GetNetworkJson() const = 0;
  virtual SettingsValues CurrentSettings() const = 0;
  virtual void OnWindowCloseRequested() = 0;
};

class Win32Shell {
 public:
  Win32Shell(HINSTANCE instance,
             ShellDelegate* delegate,
             BrowserStateObserver* observer,
             Win32BrowserView* browser_view);

  bool Create(const std::wstring& title, int width, int height);
  void Show(int show_command);
  HWND hwnd() const { return hwnd_; }
  void UpdateBrowserState(const BrowserState& state);
  void ShowToast(const std::wstring& message);
  void Close();

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void CreateMenuBar();
  void LayoutChildren(int width, int height);

  HINSTANCE instance_;
  ShellDelegate* delegate_;
  BrowserStateObserver* observer_;
  Win32BrowserView* browser_view_;
  HWND hwnd_ = nullptr;
  UrlBar url_bar_;
  ToastView toast_;
  BookmarksView bookmarks_view_;
  HistoryView history_view_;
  NetworkInspector network_view_;
};

}  // namespace kelpie::windows
