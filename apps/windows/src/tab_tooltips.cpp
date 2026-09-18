#include "tab_tooltips.h"

#include <commctrl.h>

namespace kelpie::windows {

TabStripTooltips::~TabStripTooltips() { Destroy(); }

bool TabStripTooltips::EnsureCreated(HINSTANCE instance, HWND owner) {
  if (tooltip_ != nullptr) return true;
  if (owner == nullptr) return false;
  tooltip_ = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASSW, nullptr,
                             WS_POPUP | TTS_NOPREFIX | TTS_ALWAYSTIP, CW_USEDEFAULT, CW_USEDEFAULT,
                             CW_USEDEFAULT, CW_USEDEFAULT, owner, nullptr, instance, nullptr);
  if (tooltip_ == nullptr) return false;
  // A partition id can be 128 characters, and a page title longer still. The
  // default tooltip width would clip both onto one unreadable line.
  SendMessageW(tooltip_, TTM_SETMAXTIPWIDTH, 0, 480);
  return true;
}

void TabStripTooltips::Update(HINSTANCE instance, HWND owner, HWND tab_strip,
                              const std::vector<Item>& items) {
  if (tab_strip == nullptr || !EnsureCreated(instance, owner)) return;
  // The tool ids are positional, so a strip that lost a tab must drop the
  // stale tools before re-registering — otherwise an old rect keeps answering.
  for (std::size_t index = 0; index < registered_; ++index) {
    TTTOOLINFOW tool{};
    tool.cbSize = sizeof(tool);
    tool.hwnd = tab_strip_;
    tool.uId = static_cast<UINT_PTR>(index);
    SendMessageW(tooltip_, TTM_DELTOOL, 0, reinterpret_cast<LPARAM>(&tool));
  }
  tab_strip_ = tab_strip;
  registered_ = items.size();
  for (std::size_t index = 0; index < items.size(); ++index) {
    TTTOOLINFOW tool{};
    tool.cbSize = sizeof(tool);
    // TTF_SUBCLASS lets the tooltip pull the mouse messages it needs straight
    // from the tab strip, so the shell's message loop needs no relay.
    tool.uFlags = TTF_SUBCLASS;
    tool.hwnd = tab_strip;
    tool.uId = static_cast<UINT_PTR>(index);
    tool.rect = items[index].bounds;
    tool.lpszText = const_cast<wchar_t*>(items[index].text.c_str());
    SendMessageW(tooltip_, TTM_ADDTOOLW, 0, reinterpret_cast<LPARAM>(&tool));
  }
}

void TabStripTooltips::Destroy() {
  if (tooltip_ != nullptr) {
    DestroyWindow(tooltip_);
    tooltip_ = nullptr;
  }
  tab_strip_ = nullptr;
  registered_ = 0;
}

}  // namespace kelpie::windows
