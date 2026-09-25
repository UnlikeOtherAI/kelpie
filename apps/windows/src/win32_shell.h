#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "bookmarks_view.h"
#include "history_view.h"
#include "favorites_bar.h"
#include "favicon_cache.h"
#include "theme/chrome_palette.h"
#include "network_inspector.h"
#include "settings_view.h"
#include "tab_tooltips.h"
#include "toast_view.h"
#include "url_bar.h"
#include "win32_browser_view.h"
#include "window_chrome.h"

namespace kelpie::windows {

// The macOS tab bar clamps pill widths to this range before spreading them.
inline constexpr int kTabMinWidthDip = 80;
inline constexpr int kTabMaxWidthDip = 220;

class ShellDelegate : public UrlBarDelegate {
 public:
  ~ShellDelegate() override = default;
  virtual std::string GetBookmarksJson() const = 0;
  virtual std::string GetHistoryJson() const = 0;
  virtual std::string GetNetworkJson() const = 0;
  virtual std::string GetTabsJson() const = 0;
  virtual SettingsValues CurrentSettings() const = 0;
  virtual void OnCreateTabRequested() = 0;
  virtual void OnCreateIsolatedTabRequested() = 0;
  virtual void OnActivateTabRequested(std::string id, std::uint64_t generation) = 0;
  virtual void OnCloseTabRequested(std::string id, std::uint64_t generation) = 0;
  virtual void OnWindowCloseRequested() = 0;
};

class Win32Shell {
 public:
  Win32Shell(HINSTANCE instance, ShellDelegate* delegate, BrowserStateObserver* observer,
             Win32BrowserView* browser_view);
  // `origin` places the frame in screen coordinates; without it Windows
  // picks the default position.
  bool Create(const std::wstring& title, int width, int height, std::optional<POINT> origin = std::nullopt);
  void Show(int show_command);
  HWND hwnd() const { return hwnd_; }
  HACCEL accelerators() const { return accelerators_; }
  bool HandleKeyboardNavigation(const MSG& message);
  void UpdateBrowserState(const BrowserState& state);
  void SetPageColor(COLORREF color);
  void UpdateAccount(const std::string& avatar, const std::wstring& label, bool error, bool busy) {
    url_bar_.SetAccount(avatar, label, error, busy);
  }
  void ShowToast(const std::wstring& message);
  void Close();

 private:
  struct TabItem {
    std::string id;
    std::uint64_t generation = 0;
    // What the pill prints: the caller's `name` when it set one, otherwise the
    // page title. `title` is kept for the tooltip, which stays truthful.
    TabIcon icon;
    std::string label;
    std::string title;
    std::string partition;
    bool persistent = true;
    bool active = false;
  };
  struct TabCloseButton {
    HWND hwnd = nullptr;
    std::string id;
    std::uint64_t generation = 0;
  };

  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK NewTabProc(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR);
  static LRESULT CALLBACK TabStripProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                       UINT_PTR subclass_id, DWORD_PTR reference_data);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void ApplyAppearance();
  // Re-measures the pills. The width depends on how many tabs are open, so
  // this runs when the tab set changes as well as on resize.
  void ApplyTabMetrics();
  // Width of one tab pill for a strip of this width, clamped like macOS.
  int TabWidthFor(int strip_width) const;
  void LayoutChildren(int width, int height);
  void ShowPanel(UINT command);
  bool RefreshTabs();
  void RebuildTabCloseButtons();
  void LayoutTabCloseButtons();
  // Hover text for the pills, rebuilt with their rects.
  void RefreshTabTooltips();
  // Offers "New tab" and "New isolated tab" under the split "+" control.
  void ShowNewTabMenu();
  void UpdateChromePalette();
  void PaintTabStrip(HDC dc) const;
  void PaintClient(HDC device_context) const;
  bool DrawControl(const DRAWITEMSTRUCT& item) const;
  static bool SameTabs(const std::vector<TabItem>& left, const std::vector<TabItem>& right);
  void ActivateAdjacentTab(int direction);
  void ActivateSelectedTab();
  void CloseTabAt(std::size_t index);
  std::vector<HWND> FocusOrder() const;

  HINSTANCE instance_;
  ShellDelegate* delegate_;
  BrowserStateObserver* observer_;
  Win32BrowserView* browser_view_;
  HWND hwnd_ = nullptr;
  HWND tab_strip_ = nullptr;
  HWND new_tab_button_ = nullptr;
  HACCEL accelerators_ = nullptr;
  ui::ChromeTransition chrome_transition_;
  ui::ChromePalette chrome_palette_ = ui::ChromeColors(ui::DefaultChromeColor());
  mutable FaviconCache favicon_cache_;
  FavoritesBar favorites_bar_;
  WindowChrome window_chrome_;
  UrlBar url_bar_;
  ToastView toast_;
  TabStripTooltips tab_tooltips_;
  BookmarksView bookmarks_view_;
  HistoryView history_view_;
  NetworkInspector network_view_;
  std::vector<TabItem> tabs_;
  std::vector<TabCloseButton> tab_close_buttons_;
  std::string active_tab_id_;
  BrowserState browser_state_;
  bool has_browser_state_ = false;
};

}  // namespace kelpie::windows
