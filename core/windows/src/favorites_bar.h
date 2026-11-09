#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>
#include "drag_effects.h"
#include "theme/chrome_palette.h"

namespace kelpie::windows {

// The row of favourites under the address bar.
//
// Click opens a favourite. Dragging one lifts it out of the row so it follows
// the pointer; dropping it well outside the row removes it with a puff, and
// dropping it anywhere else, or pressing Escape, glides it back.
class FavoritesBar {
 public:
  void Attach(HWND parent, HINSTANCE instance, std::function<void(const std::string&)> navigate,
              std::function<void(const std::string& id)> remove);
  bool Update(const std::string& json);
  void Layout(RECT bounds);
  int Height() const;
  bool DrawControl(const DRAWITEMSTRUCT& item) const;
  bool HandleCommand(UINT id);
  void SetPalette(ui::ChromePalette palette) { palette_ = palette; }
  std::vector<HWND> FocusableControls() const;
 private:
  struct Favorite { std::wstring title; std::string url; std::string id; HWND button; };
  // A press on a favourite that may become a drag once it moves far enough.
  struct Drag {
    bool pressed = false;
    bool active = false;
    std::size_t index = 0;
    POINT start{};  // Screen coordinates of the press.
    POINT grab{};   // The press inside the item.
  };

  static LRESULT CALLBACK ItemProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                   UINT_PTR subclass_id, DWORD_PTR reference);
  bool HandleItemMessage(HWND button, UINT message, WPARAM wparam, LPARAM lparam);
  std::size_t IndexOf(HWND button) const;
  void BeginDrag();
  void FinishDrag(bool dropped, POINT screen);
  bool IsRemovalPoint(POINT screen) const;
  // The favicon avatar and title, without a background.
  void PaintContent(HDC dc, RECT rect, std::size_t index) const;
  HBITMAP RenderItem(std::size_t index, SIZE size) const;

  HWND parent_ = nullptr, overflow_ = nullptr;
  HINSTANCE instance_ = nullptr;
  std::string json_;
  std::vector<Favorite> items_;
  std::size_t visible_ = 0;
  RECT bounds_{};
  std::function<void(const std::string&)> navigate_;
  std::function<void(const std::string&)> remove_;
  Drag drag_;
  DragGhost ghost_;
  // The favourite whose ghost is gliding back; its slot stays empty until the
  // ghost lands, so the item is never shown twice.
  HWND returning_ = nullptr;
  // A favourite removed by dragging stays hidden until the favourites change,
  // or briefly at most, so a slow account save does not flash it back.
  std::string hidden_id_;
  std::uint64_t hidden_until_ = 0;
  ui::ChromePalette palette_ = ui::ChromeColors(ui::DefaultChromeColor());
};

}  // namespace kelpie::windows
