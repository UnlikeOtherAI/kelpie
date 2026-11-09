#include "favorites_bar.h"

#include <algorithm>
#include <commctrl.h>
#include <nlohmann/json.hpp>
#include "theme/theme.h"
#include "letter_avatar.h"
#include "favicon_cache.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {
constexpr int kFirst = 3000;
constexpr int kOverflow = 3999;
constexpr UINT_PTR kItemSubclass = 1;
// How long a dragged-off favourite stays hidden while its removal saves.
constexpr std::uint64_t kHiddenMs = 8000;
}

void FavoritesBar::Attach(HWND parent, HINSTANCE instance,
                          std::function<void(const std::string&)> navigate,
                          std::function<void(const std::string& id)> remove) {
  parent_ = parent;
  instance_ = instance;
  navigate_ = std::move(navigate);
  remove_ = std::move(remove);
  overflow_ = CreateWindowExW(0, L"BUTTON", L"More favorites",
      WS_CHILD | WS_TABSTOP | BS_OWNERDRAW, 0, 0, 0, 0, parent,
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(kOverflow)), instance, nullptr);
}

bool FavoritesBar::Update(const std::string& json) {
  // Rebuilding destroys the buttons, and with them the pointer capture of a
  // drag in progress; pick the change up on the next refresh instead.
  if (drag_.active) return false;
  if (json == json_) {
    if (hidden_id_.empty() || GetTickCount64() < hidden_until_) return false;
    hidden_id_.clear();
    return true;
  }
  const auto parsed = nlohmann::json::parse(json, nullptr, false);
  if (!parsed.is_array()) return false;
  for (const auto& item : items_) DestroyWindow(item.button);
  items_.clear();
  drag_ = {};
  returning_ = nullptr;
  hidden_id_.clear();
  json_ = json;
  for (const auto& entry : parsed) {
    if (!entry.is_object() || !entry.contains("url") || !entry["url"].is_string()) continue;
    const auto url = entry["url"].get<std::string>();
    if (url.empty()) continue;
    const auto title = entry.contains("title") && entry["title"].is_string()
        ? entry["title"].get<std::string>() : url;
    const auto id = entry.contains("id") && entry["id"].is_string() ? entry["id"].get<std::string>() : std::string();
    // Control IDs must never collide with overflow or unrelated shell commands.
    const int control = kFirst + static_cast<int>(std::min<std::size_t>(items_.size(), 998));
    HWND button = items_.size() < 999 ? CreateWindowExW(0, L"BUTTON",
        utf::Utf8ToWideDisplay(title.empty() ? url : title).c_str(),
        WS_CHILD | WS_TABSTOP | BS_OWNERDRAW, 0, 0, 0, 0, parent_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(control)), instance_, nullptr) : nullptr;
    if (button) SetWindowSubclass(button, &FavoritesBar::ItemProc, kItemSubclass, reinterpret_cast<DWORD_PTR>(this));
    items_.push_back({utf::Utf8ToWideDisplay(title.empty() ? url : title), url, id, button});
  }
  return true;
}

int FavoritesBar::Height() const { return items_.empty() ? 0 : ui::Dip(parent_, 44); }

void FavoritesBar::Layout(RECT bounds) {
  bounds_ = bounds;
  const int gap = ui::Dip(parent_, 12);
  const int overflow_width = ui::Dip(parent_, 32);
  int left = bounds.left + gap;
  visible_ = 0;
  HDC dc = GetDC(parent_);
  const auto font = SelectObject(dc, ui::CachedFont(parent_, 13));
  bool full = false;
  for (auto& item : items_) {
    if (!hidden_id_.empty() && item.id == hidden_id_) {
      if (item.button) ShowWindow(item.button, SW_HIDE);
      continue;
    }
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
  const auto shown = std::count_if(items_.begin(), items_.end(), [this](const Favorite& item) {
    return hidden_id_.empty() || item.id != hidden_id_;
  });
  ShowWindow(overflow_, visible_ < static_cast<std::size_t>(shown) ? SW_SHOWNA : SW_HIDE);
}

void FavoritesBar::PaintContent(HDC dc, RECT rect, std::size_t index) const {
  if (index >= items_.size()) return;
  const int icon = ui::Dip(parent_, 16), pad = ui::Dip(parent_, 6);
  const int top = rect.top + (rect.bottom - rect.top - icon) / 2;
  DrawLetterAvatar(dc, RECT{rect.left + pad, top, rect.left + pad + icon, top + icon},
                   FaviconCache::HostForUrl(items_[index].url));
  RECT text = rect;
  text.left += ui::Dip(parent_, 30);
  text.right -= pad;
  ui::DrawLabel(dc, parent_, text, items_[index].title.c_str(), palette_.text, 13);
}

bool FavoritesBar::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (item.CtlID < kFirst || item.CtlID > kOverflow) return false;
  const bool focused = (item.itemState & ODS_FOCUS) != 0;
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  if (item.CtlID == kOverflow) {
    ui::FillSolid(item.hDC, item.rcItem, palette_.bar);
    if (pressed || focused) ui::PaintRounded(item.hDC, item.rcItem, palette_.hover,
        focused ? ui::Colors().focus : palette_.hover, ui::Dip(parent_, 6));
    ui::DrawGlyph(item.hDC, parent_, item.rcItem, L'', palette_.text, 14);
    return true;
  }
  const auto index = item.CtlID - kFirst;
  if ((drag_.active && index == drag_.index) || (returning_ != nullptr && item.hwndItem == returning_)) {
    // The lifted favourite leaves an empty slot behind.
    ui::FillSolid(item.hDC, item.rcItem, palette_.bar);
    ui::PaintRounded(item.hDC, item.rcItem, palette_.bar, palette_.hover, ui::Dip(parent_, 6), ui::Dip(parent_, 1));
    return true;
  }
  ui::FillSolid(item.hDC, item.rcItem, palette_.bar);
  if (pressed || focused) ui::PaintRounded(item.hDC, item.rcItem, palette_.hover,
      focused ? ui::Colors().focus : palette_.hover, ui::Dip(parent_, 6));
  PaintContent(item.hDC, item.rcItem, index);
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
    if (!hidden_id_.empty() && items_[i].id == hidden_id_) continue;
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

// --- Dragging a favourite off the bar --------------------------------------

std::size_t FavoritesBar::IndexOf(HWND button) const {
  for (std::size_t index = 0; index < items_.size(); ++index) {
    if (items_[index].button == button) return index;
  }
  return items_.size();
}

LRESULT CALLBACK FavoritesBar::ItemProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                        UINT_PTR, DWORD_PTR reference) {
  if (message == WM_NCDESTROY) RemoveWindowSubclass(hwnd, &FavoritesBar::ItemProc, kItemSubclass);
  auto* bar = reinterpret_cast<FavoritesBar*>(reference);
  if (bar != nullptr && bar->HandleItemMessage(hwnd, message, wparam, lparam)) return 0;
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

// Returns true when the message was consumed. While a drag is active the
// button's own handling is skipped, so it neither repaints as pressed nor
// reports a click when the drag ends.
bool FavoritesBar::HandleItemMessage(HWND button, UINT message, WPARAM wparam, LPARAM lparam) {
  POINT screen{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
  switch (message) {
    case WM_LBUTTONDOWN: {
      const std::size_t index = IndexOf(button);
      if (index >= items_.size()) return false;
      drag_ = {};
      drag_.pressed = true;
      drag_.index = index;
      drag_.grab = screen;
      ClientToScreen(button, &screen);
      drag_.start = screen;
      return false;
    }
    case WM_MOUSEMOVE: {
      if (!drag_.pressed || (wparam & MK_LBUTTON) == 0) return false;
      ClientToScreen(button, &screen);
      if (!drag_.active) {
        const bool moved = std::abs(screen.x - drag_.start.x) > GetSystemMetrics(SM_CXDRAG) ||
                           std::abs(screen.y - drag_.start.y) > GetSystemMetrics(SM_CYDRAG);
        if (!moved) return false;
        BeginDrag();
      }
      ghost_.Move(screen, IsRemovalPoint(screen));
      return true;
    }
    case WM_LBUTTONUP: {
      if (!drag_.active) {
        drag_ = {};
        return false;
      }
      ClientToScreen(button, &screen);
      FinishDrag(true, screen);
      return true;
    }
    case WM_KEYDOWN:
      if (drag_.active && wparam == VK_ESCAPE) {
        POINT cursor{};
        GetCursorPos(&cursor);
        FinishDrag(false, cursor);
        return true;
      }
      return false;
    case WM_CAPTURECHANGED:
      // Another window took the pointer (a menu, a dialog, a lost focus). The
      // button still sees the message so it drops its own pressed tracking.
      if (drag_.active && reinterpret_cast<HWND>(lparam) != button) {
        POINT cursor{};
        GetCursorPos(&cursor);
        FinishDrag(false, cursor);
      }
      return false;
    default:
      return false;
  }
}

void FavoritesBar::BeginDrag() {
  const std::size_t index = drag_.index;
  if (index >= items_.size() || items_[index].button == nullptr) return;
  HWND button = items_[index].button;
  RECT rect{};
  GetClientRect(button, &rect);
  const SIZE size{rect.right - rect.left, rect.bottom - rect.top};
  HBITMAP image = RenderItem(index, size);
  drag_.active = true;
  // Keep the pointer after the button's own pressed state is cleared.
  SendMessageW(button, BM_SETSTATE, FALSE, 0);
  if (GetCapture() != button) SetCapture(button);
  if (image) {
    ghost_.Show(parent_, image, size, drag_.grab, ui::Dip(parent_, 8));
    DeleteObject(image);
  }
  InvalidateRect(button, nullptr, TRUE);
}

void FavoritesBar::FinishDrag(bool dropped, POINT screen) {
  const std::size_t index = drag_.index;
  // Clear the drag first: releasing capture re-enters WM_CAPTURECHANGED.
  drag_ = {};
  if (GetCapture() != nullptr && index < items_.size() && GetCapture() == items_[index].button) ReleaseCapture();
  if (index >= items_.size()) {
    ghost_.Hide();
    return;
  }
  Favorite& item = items_[index];
  if (dropped && IsRemovalPoint(screen) && !item.id.empty() && remove_) {
    ghost_.Hide();
    ShowRemovalPuff(parent_, screen);
    hidden_id_ = item.id;
    hidden_until_ = GetTickCount64() + kHiddenMs;
    Layout(bounds_);
    // Copied: the owner may refresh the bar, which rebuilds `items_`.
    const std::string id = item.id;
    remove_(id);
    return;
  }
  RECT slot{};
  GetWindowRect(item.button, &slot);
  HWND button = item.button;
  returning_ = button;
  InvalidateRect(button, nullptr, TRUE);
  ghost_.ReturnTo(POINT{slot.left, slot.top}, [this, button] {
    if (returning_ == button) returning_ = nullptr;
    if (IsWindow(button)) InvalidateRect(button, nullptr, TRUE);
  });
}

bool FavoritesBar::IsRemovalPoint(POINT screen) const {
  RECT bar = bounds_;
  bar.bottom = bar.top + Height();
  MapWindowPoints(parent_, nullptr, reinterpret_cast<POINT*>(&bar), 2);
  InflateRect(&bar, ui::Dip(parent_, 32), ui::Dip(parent_, 32));
  return !PtInRect(&bar, screen);
}

HBITMAP FavoritesBar::RenderItem(std::size_t index, SIZE size) const {
  if (size.cx <= 0 || size.cy <= 0) return nullptr;
  HDC screen = GetDC(nullptr);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, size.cx, size.cy);
  HDC memory = CreateCompatibleDC(screen);
  ReleaseDC(nullptr, screen);
  if (bitmap == nullptr || memory == nullptr) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    return nullptr;
  }
  const HGDIOBJ previous = SelectObject(memory, bitmap);
  const RECT rect{0, 0, size.cx, size.cy};
  ui::FillSolid(memory, rect, palette_.hover);
  PaintContent(memory, rect, index);
  SelectObject(memory, previous);
  DeleteDC(memory);
  return bitmap;
}

}  // namespace kelpie::windows
