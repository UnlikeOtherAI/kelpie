#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows {

// A resizable utility window owned by the browser: Bookmarks, History and the
// Network inspector. It opens centred over the browser window at the browser's
// DPI, keeps a usable minimum size, and survives being closed with its title
// bar button so the toolbar can show it again.
class PanelWindow {
 public:
  virtual ~PanelWindow() = default;
  // Shows the panel, creating it centred over `owner` on first use, or hides it
  // when it is already showing.
  void Toggle(HINSTANCE instance, HWND owner);
  void Hide();
  bool IsShowing() const;
  HWND hwnd() const { return hwnd_; }

 protected:
  struct Spec {
    const wchar_t* class_name;
    const wchar_t* title;
    SIZE size_dip;      // initial client size
    SIZE min_size_dip;  // smallest client size that still shows its controls
  };

  virtual Spec Describe() const = 0;
  // Creates the child controls once the window exists.
  virtual void CreateControls() = 0;
  virtual void Layout(const RECT& client) = 0;
  // Re-applies `font_` and the palette after a DPI or theme change.
  virtual void ApplyTheme() = 0;
  virtual void OnShown() {}
  // Messages the panel handles itself. Return true when handled.
  virtual bool HandlePanelMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result) {
    (void)message;
    (void)wparam;
    (void)lparam;
    (void)result;
    return false;
  }

  HINSTANCE instance_ = nullptr;
  HWND owner_ = nullptr;
  HWND hwnd_ = nullptr;
  HFONT font_ = nullptr;

 private:
  static constexpr DWORD kStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME |
                                  WS_MAXIMIZEBOX | WS_CLIPCHILDREN;
  static constexpr DWORD kExStyle = WS_EX_CONTROLPARENT;

  bool Create(HINSTANCE instance, HWND owner);
  void RefreshFont();
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
};

}  // namespace kelpie::windows
