#include "favorites_bar.h"

#include <algorithm>
#include <nlohmann/json.hpp>
#include "theme/theme.h"
#include "letter_avatar.h"
#include "favicon_cache.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {
constexpr int kFirst = 3000;
constexpr int kOverflow = 3999;
}

void FavoritesBar::Attach(HWND parent, HINSTANCE instance,
                          std::function<void(const std::string&)> navigate) {
  parent_ = parent;
  instance_ = instance;
  navigate_ = std::move(navigate);
  overflow_ = CreateWindowExW(0, L"BUTTON", L"More favorites",
      WS_CHILD | WS_TABSTOP | BS_OWNERDRAW, 0, 0, 0, 0, parent,
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(kOverflow)), instance, nullptr);
}

bool FavoritesBar::Update(const std::string& json) {
  if (json == json_) return false;
  const auto parsed = nlohmann::json::parse(json, nullptr, false);
  if (!parsed.is_array()) return false;
  for (const auto& item : items_) DestroyWindow(item.button);
  items_.clear();
  json_ = json;
  for (const auto& entry : parsed) {
    if (!entry.is_object() || !entry.contains("url") || !entry["url"].is_string()) continue;
    const auto url = entry["url"].get<std::string>();
    if (url.empty()) continue;
    const auto title = entry.contains("title") && entry["title"].is_string()
        ? entry["title"].get<std::string>() : url;
    // Control IDs must never collide with overflow or unrelated shell commands.
    const int id = kFirst + static_cast<int>(std::min<std::size_t>(items_.size(), 998));
    HWND button = items_.size() < 999 ? CreateWindowExW(0, L"BUTTON",
        utf::Utf8ToWideDisplay(title.empty() ? url : title).c_str(),
        WS_CHILD | WS_TABSTOP | BS_OWNERDRAW, 0, 0, 0, 0, parent_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), instance_, nullptr) : nullptr;
    items_.push_back({utf::Utf8ToWideDisplay(title.empty() ? url : title), url, button});
  }
  return true;
}

int FavoritesBar::Height() const { return items_.empty() ? 0 : ui::Dip(parent_, 44); }

void FavoritesBar::Layout(RECT bounds) {
  const int gap = ui::Dip(parent_, 12);
  const int overflow_width = ui::Dip(parent_, 32);
  int left = bounds.left + gap;
  visible_ = 0;
  HDC dc = GetDC(parent_);
  const auto font = SelectObject(dc, ui::CachedFont(parent_, 13));
  bool full = false;
  for (auto& item : items_) {
    SIZE size{};
    GetTextExtentPoint32W(dc, item.title.c_str(), static_cast<int>(item.title.size()), &size);
    const int width = std::clamp(static_cast<int>(size.cx) + ui::Dip(parent_, 38),
                                ui::Dip(parent_, 64), ui::Dip(parent_, 180));
    full = full || !item.button || left + width > bounds.right - gap - overflow_width;
    if (full) { if (item.button) ShowWindow(item.button, SW_HIDE); continue; }
    SetWindowPos(item.button, nullptr, left, bounds.top + ui::Dip(parent_, 4), width,
                 Height() - ui::Dip(parent_, 8), SWP_NOZORDER | SWP_SHOWWINDOW | SWP_NOACTIVATE);
    left += width + gap;
    ++visible_;
  }
  SelectObject(dc, font);
  ReleaseDC(parent_, dc);
  SetWindowPos(overflow_, nullptr, bounds.right - gap - overflow_width, bounds.top,
               overflow_width, Height(), SWP_NOZORDER | SWP_NOACTIVATE);
  ShowWindow(overflow_, visible_ < items_.size() ? SW_SHOWNA : SW_HIDE);
}

bool FavoritesBar::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (item.CtlID < kFirst || item.CtlID > kOverflow) return false;
  const bool focused = (item.itemState & ODS_FOCUS) != 0;
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  ui::FillSolid(item.hDC, item.rcItem, palette_.bar);
  if (pressed || focused) ui::PaintRounded(item.hDC, item.rcItem, palette_.hover,
      focused ? ui::Colors().focus : palette_.hover, ui::Dip(parent_, 6));
  if (item.CtlID == kOverflow) {
    ui::DrawGlyph(item.hDC, parent_, item.rcItem, L'\uE76C', palette_.text, 14);
    return true;
  }
  const auto index = item.CtlID - kFirst;
  if (index >= items_.size()) return true;
  const int icon = ui::Dip(parent_, 16), pad = ui::Dip(parent_, 6);
  const int top = (item.rcItem.bottom - icon) / 2;
  DrawLetterAvatar(item.hDC, RECT{pad, top, pad+icon, top+icon}, FaviconCache::HostForUrl(items_[index].url));
  RECT text = item.rcItem;
  text.left += ui::Dip(parent_, 30);
  text.right -= pad;
  ui::DrawLabel(item.hDC, parent_, text, items_[index].title.c_str(), palette_.text, 13);
  return true;
}

bool FavoritesBar::HandleCommand(UINT id) {
  if (id < kFirst || id > kOverflow) return false;
  if (id != kOverflow) {
    if (id - kFirst < items_.size() && navigate_) navigate_(items_[id-kFirst].url);
    return true;
  }
  HMENU menu = CreatePopupMenu();
  if (!menu) return true;
  for (std::size_t i = visible_; i < items_.size(); ++i) {
    std::wstring title;
    for (wchar_t c : items_[i].title) { title += c; if (c == L'&') title += c; }
    AppendMenuW(menu, MF_STRING, static_cast<UINT_PTR>(i+1), title.c_str());
  }
  RECT rect{};
  GetWindowRect(overflow_, &rect);
  const UINT selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTALIGN,
      rect.right, rect.bottom, 0, parent_, nullptr);
  DestroyMenu(menu);
  if (selected > 0 && selected <= items_.size() && navigate_) navigate_(items_[selected-1].url);
  return true;
}

std::vector<HWND> FavoritesBar::FocusableControls() const {
  std::vector<HWND> result;
  for (const auto& item : items_) if (IsWindowVisible(item.button)) result.push_back(item.button);
  if (IsWindowVisible(overflow_)) result.push_back(overflow_);
  return result;
}

}  // namespace kelpie::windows
