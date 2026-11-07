#pragma once

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

// Hover text for the tab pills.
//
// A pill is 80-200 DIP wide, so its label is almost always truncated and a
// partitioned pill shows a short `name` rather than the page title. The
// tooltip is where the full title, and the partition the tab is bound to,
// remain readable — it is the only place the partition id is spelled out in
// the chrome.
//
// This lives apart from Win32Shell because it owns a window and a tool
// registration of its own, and the shell is already at the file-size limit.
class TabStripTooltips {
 public:
  struct Item {
    RECT bounds{};  // in the tab strip's client coordinates
    std::wstring text;
  };

  ~TabStripTooltips();

  TabStripTooltips(const TabStripTooltips&) = delete;
  TabStripTooltips& operator=(const TabStripTooltips&) = delete;
  TabStripTooltips() = default;

  // Replaces the registered tools. Safe to call on every relayout: the rects
  // move whenever the strip scrolls or the pill width changes.
  void Update(HINSTANCE instance, HWND owner, HWND tab_strip, const std::vector<Item>& items);
  void Destroy();

  HWND hwnd() const { return tooltip_; }

 private:
  bool EnsureCreated(HINSTANCE instance, HWND owner);

  HWND tooltip_ = nullptr;
  HWND tab_strip_ = nullptr;
  std::size_t registered_ = 0;
};

}  // namespace kelpie::windows
