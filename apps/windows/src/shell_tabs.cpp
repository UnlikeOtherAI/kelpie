#include "win32_shell.h"
#include <commctrl.h>
#include <windowsx.h>
#include <algorithm>
#include <nlohmann/json.hpp>
#include "../resources/resource.h"
#include "theme/theme.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {
constexpr int kTabCloseFirst = 2000;
bool IsTabClose(UINT id) { return id >= kTabCloseFirst && id < kTabCloseFirst + 256; }
}
bool Win32Shell::RefreshTabs() {
  if (tab_strip_ == nullptr || delegate_ == nullptr) return false;
  const nlohmann::json parsed = nlohmann::json::parse(delegate_->GetTabsJson(), nullptr, false);
  const nlohmann::json* entries = parsed.is_object() && parsed.contains("tabs") ? &parsed["tabs"] : &parsed;
  if (!entries->is_array()) return false;
  std::vector<TabItem> next;
  std::string active;
  for (const auto& entry : *entries) {
    if (!entry.is_object()) continue;
    const std::string id = entry.value("id", "");
    if (id.empty()) continue;
    std::string title = entry.value("title", "");
    if (title.empty()) title = entry.value("url", "");
    if (title.empty()) title = "New tab";
    // A named tab prints its name: the point of naming one is that the page
    // title is not what identifies it.
    const std::string name = entry.value("name", "");
    const bool selected = entry.value("active", false);
    TabItem item;
    item.icon = {entry.value("url", ""), entry.value("favicon", ""), entry.value("isStartPage", false)};
    favicon_cache_.Update(item.icon);
    item.id = id;
    item.generation = entry.value("generation", std::uint64_t{0});
    item.label = name.empty() ? title : name;
    item.title = title;
    item.partition = entry.value("partition", "");
    item.persistent = entry.value("persistent", true);
    item.active = selected;
    next.push_back(std::move(item));
    if (selected) active = id;
  }
  if (SameTabs(tabs_, next) && active_tab_id_ == active) return false;
  const bool active_changed = active_tab_id_ != active;
  tabs_ = std::move(next);
  active_tab_id_ = active;
  TabCtrl_DeleteAllItems(tab_strip_);
  int selected = -1;
  for (std::size_t index = 0; index < tabs_.size(); ++index) {
    std::wstring text = utf::Utf8ToWideDisplay(tabs_[index].label);
    TCITEMW item{};
    item.mask = TCIF_TEXT;
    item.pszText = text.data();
    TabCtrl_InsertItem(tab_strip_, static_cast<int>(index), &item);
    if (tabs_[index].active) selected = static_cast<int>(index);
  }
  TabCtrl_SetCurSel(tab_strip_, selected >= 0 ? selected : 0);
  ApplyTabMetrics();
  RebuildTabCloseButtons();
  InvalidateRect(tab_strip_, nullptr, FALSE);
  return active_changed;
}

void Win32Shell::RebuildTabCloseButtons() {
  for (const auto& button : tab_close_buttons_) if (button.hwnd != nullptr) DestroyWindow(button.hwnd);
  tab_close_buttons_.clear();
  for (std::size_t index = 0; index < tabs_.size() && index < 256; ++index) {
    const auto& tab = tabs_[index];
    const std::wstring title = utf::Utf8ToWideDisplay(tab.label);
    HWND button = CreateWindowExW(0, L"BUTTON", (L"Close " + title).c_str(), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                                  0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTabCloseFirst + index)), instance_, nullptr);
    tab_close_buttons_.push_back({button, tab.id, tab.generation});
  }
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  LayoutChildren(rect.right, rect.bottom);
}

void Win32Shell::LayoutTabCloseButtons() {
  RECT strip{};
  GetClientRect(tab_strip_, &strip);
  MapWindowPoints(tab_strip_, hwnd_, reinterpret_cast<POINT*>(&strip), 2);
  HWND scroll = FindWindowExW(tab_strip_, nullptr, UPDOWN_CLASSW, nullptr);
  if (scroll != nullptr && (GetWindowLongPtrW(scroll, GWL_STYLE) & WS_VISIBLE) != 0) {
    RECT scroll_rect{};
    GetWindowRect(scroll, &scroll_rect);
    MapWindowPoints(HWND_DESKTOP, hwnd_, reinterpret_cast<POINT*>(&scroll_rect), 2);
    strip.right = std::min(strip.right, scroll_rect.left);
  }
  for (std::size_t index = 0; index < tab_close_buttons_.size(); ++index) {
    RECT item{};
    if (!TabCtrl_GetItemRect(tab_strip_, static_cast<int>(index), &item)) {
      ShowWindow(tab_close_buttons_[index].hwnd, SW_HIDE);
      continue;
    }
    item.top = 0;
    item.bottom = strip.bottom-strip.top;
    MapWindowPoints(tab_strip_, hwnd_, reinterpret_cast<POINT*>(&item), 2);
    const int size = ui::Dip(hwnd_, 18);
    const int left = item.right - size - ui::Dip(hwnd_, 14);
    const bool visible = left >= strip.left && left + size <= strip.right &&
                         item.top >= strip.top && item.bottom <= strip.bottom;
    if (!visible) {
      ShowWindow(tab_close_buttons_[index].hwnd, SW_HIDE);
      continue;
    }
    SetWindowPos(tab_close_buttons_[index].hwnd, HWND_TOP, left,
                 item.top + (item.bottom - item.top - size) / 2, size, size,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  }
  RefreshTabTooltips();
}

void Win32Shell::RefreshTabTooltips() {
  if (tab_strip_ == nullptr) return;
  std::vector<TabStripTooltips::Item> items;
  items.reserve(tabs_.size());
  for (std::size_t index = 0; index < tabs_.size(); ++index) {
    RECT bounds{};
    if (!TabCtrl_GetItemRect(tab_strip_, static_cast<int>(index), &bounds)) continue;
    // The pill may be showing a short name, so the tooltip is where the real
    // page title and the partition id stay readable.
    std::wstring text = utf::Utf8ToWideDisplay(tabs_[index].title);
    if (!tabs_[index].partition.empty()) {
      text += L"\nPartition: " + utf::Utf8ToWideDisplay(tabs_[index].partition);
      if (!tabs_[index].persistent) text += L" (in memory only)";
    }
    items.push_back({bounds, std::move(text)});
  }
  tab_tooltips_.Update(instance_, hwnd_, tab_strip_, items);
}

void Win32Shell::ShowNewTabMenu() {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, IDM_NEW_TAB, L"New tab\tCtrl+T");
  AppendMenuW(menu, MF_STRING, IDM_NEW_ISOLATED_TAB, L"New isolated tab\tCtrl+Shift+N");
  SetMenuDefaultItem(menu, IDM_NEW_TAB, FALSE);
  RECT bounds{};
  GetWindowRect(new_tab_button_, &bounds);
  TrackPopupMenu(menu, TPM_RIGHTALIGN | TPM_TOPALIGN | TPM_RIGHTBUTTON, bounds.right, bounds.bottom,
                 0, hwnd_, nullptr);
  DestroyMenu(menu);
}

bool Win32Shell::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (window_chrome_.DrawControl(item) || url_bar_.DrawControl(item) || favorites_bar_.DrawControl(item)) return true;
  const auto& p = chrome_palette_;
  if (item.CtlID == IDC_NEW_TAB_BUTTON) {
    ui::FillSolid(item.hDC, item.rcItem, p.caption);
    if (item.itemState & (ODS_SELECTED | ODS_FOCUS)) ui::PaintRounded(item.hDC, item.rcItem,
        p.hover, (item.itemState & ODS_FOCUS) ? ui::Colors().focus : p.hover, ui::Dip(hwnd_,8));
    ui::DrawGlyph(item.hDC, hwnd_, item.rcItem, ui::icon::kNewTab, p.caption_text, 20);
    return true;
  }
  if (IsTabClose(item.CtlID)) {
    const auto index = item.CtlID-kTabCloseFirst;
    const bool selected = index < tabs_.size() && tabs_[index].active;
    const COLORREF base = selected ? p.bar : p.caption;
    ui::FillSolid(item.hDC, item.rcItem, base);
    if (item.itemState & (ODS_SELECTED | ODS_FOCUS)) ui::PaintRounded(item.hDC, item.rcItem,
        p.hover, (item.itemState & ODS_FOCUS) ? ui::Colors().focus : p.hover, ui::Dip(hwnd_,4));
    ui::DrawGlyph(item.hDC, hwnd_, item.rcItem, ui::icon::kClose, selected ? p.text : ui::Blend(p.caption_text,p.caption,0.57), 10);
    return true;
  }
  if (item.CtlID != IDC_TAB_STRIP || item.itemID >= tabs_.size()) return false;
  const TabItem& tab = tabs_[item.itemID];
  const bool selected = tab.active;
  if (selected) {
    ui::PaintBrowserTab(item.hDC, item.rcItem, p.bar, ui::Blend(p.text,p.bar,0.12), ui::Dip(hwnd_,9));
  } else {
    const RECT divider{item.rcItem.right-1, item.rcItem.top+ui::Dip(hwnd_,10),
        item.rcItem.right, item.rcItem.bottom-ui::Dip(hwnd_,10)};
    ui::FillSolid(item.hDC, divider, ui::Blend(p.caption_text,p.caption,0.16));
  }
  RECT icon = item.rcItem;
  icon.left += ui::Dip(hwnd_,20);
  icon.right = icon.left + ui::Dip(hwnd_,18);
  icon.top += (icon.bottom-icon.top-ui::Dip(hwnd_,18))/2;
  icon.bottom = icon.top+ui::Dip(hwnd_,18);
  DrawTabIcon(item.hDC, icon, tab.icon, favicon_cache_);
  RECT text = item.rcItem;
  text.left = icon.right+ui::Dip(hwnd_,10);
  text.right -= ui::Dip(hwnd_,32);
  ui::DrawLabel(item.hDC, hwnd_, text, utf::Utf8ToWideDisplay(tab.label).c_str(),
                 selected ? p.text : ui::Blend(p.caption_text,p.caption,0.85), 13);
  if (GetFocus() == tab_strip_ && selected) {
    RECT focus = text;
    InflateRect(&focus, 1, -ui::Dip(hwnd_,10));
    DrawFocusRect(item.hDC, &focus);
  }
  if (!tab.partition.empty()) {
    const RECT accent{item.rcItem.left+ui::Dip(hwnd_,18), item.rcItem.bottom-ui::Dip(hwnd_,3),
                      item.rcItem.right-ui::Dip(hwnd_,18), item.rcItem.bottom-ui::Dip(hwnd_,1)};
    ui::FillSolid(item.hDC, accent, ui::Colors().accent);
  }
  return true;
}

bool Win32Shell::SameTabs(const std::vector<TabItem>& left, const std::vector<TabItem>& right) {
  if (left.size() != right.size()) return false;
  for (std::size_t index = 0; index < left.size(); ++index) {
    if (left[index].id != right[index].id || left[index].generation != right[index].generation ||
        left[index].icon.url != right[index].icon.url ||
        left[index].icon.favicon_png_base64 != right[index].icon.favicon_png_base64 ||
        left[index].icon.is_start_page != right[index].icon.is_start_page ||
        left[index].label != right[index].label || left[index].active != right[index].active ||
        left[index].title != right[index].title || left[index].partition != right[index].partition ||
        left[index].persistent != right[index].persistent) return false;
  }
  return true;
}

void Win32Shell::ActivateAdjacentTab(int direction) {
  if (tabs_.empty()) return;
  const int current = std::max(0, TabCtrl_GetCurSel(tab_strip_));
  TabCtrl_SetCurSel(tab_strip_, (current + direction + static_cast<int>(tabs_.size())) % static_cast<int>(tabs_.size()));
  ActivateSelectedTab();
}

void Win32Shell::ActivateSelectedTab() {
  const int selected = TabCtrl_GetCurSel(tab_strip_);
  if (selected >= 0 && static_cast<std::size_t>(selected) < tabs_.size()) {
    const auto& tab = tabs_[selected];
    delegate_->OnActivateTabRequested(tab.id, tab.generation);
    browser_view_->Focus();
  }
}

void Win32Shell::CloseTabAt(std::size_t index) {
  if (index < tabs_.size()) delegate_->OnCloseTabRequested(tabs_[index].id, tabs_[index].generation);
}

std::vector<HWND> Win32Shell::FocusOrder() const {
  std::vector<HWND> controls = window_chrome_.FocusableControls();
  const std::vector<HWND> toolbar = url_bar_.FocusableControls();
  controls.insert(controls.end(), toolbar.begin(), toolbar.end());
  if (tab_strip_ != nullptr && IsWindowVisible(tab_strip_) && IsWindowEnabled(tab_strip_)) controls.push_back(tab_strip_);
  for (const TabCloseButton& button : tab_close_buttons_) {
    if (button.hwnd != nullptr && IsWindowVisible(button.hwnd) && IsWindowEnabled(button.hwnd)) controls.push_back(button.hwnd);
  }
  if (new_tab_button_ != nullptr && IsWindowVisible(new_tab_button_) && IsWindowEnabled(new_tab_button_)) controls.push_back(new_tab_button_);
  const auto favorites = favorites_bar_.FocusableControls();
  controls.insert(controls.end(), favorites.begin(), favorites.end());
  return controls;
}

}  // namespace kelpie::windows
