#pragma once

#include <functional>
#include <memory>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

// Visual feedback for dragging a favourite off the favourites bar: the lifted
// item that follows the pointer, and the cloud puff that plays where it is
// dropped to remove it. Both are layered, click-through, non-activating popups,
// so they float above the browser without taking focus or input.
namespace kelpie::windows {

class DragGhost {
 public:
  DragGhost();
  ~DragGhost();
  DragGhost(const DragGhost&) = delete;
  DragGhost& operator=(const DragGhost&) = delete;

  // Lifts a copy of `content`, an opaque `size` bitmap of the item, with
  // rounded corners and a soft shadow. `grab` is where the pointer holds the
  // item, relative to its top-left corner, so the item does not jump.
  bool Show(HWND owner, HBITMAP content, SIZE size, POINT grab, int corner_radius);
  // Follows the pointer. `removing` marks the item for removal: it fades a
  // little and shows a remove badge.
  void Move(POINT screen, bool removing);
  // Glides back to `slot` (screen coordinates of the item's top-left corner),
  // then hides and calls `landed`. Used when a drag is cancelled or ends on
  // the bar. `landed` also runs if the ghost is hidden before it arrives.
  void ReturnTo(POINT slot, std::function<void()> landed);
  void Hide();
  bool visible() const { return window_ != nullptr; }

 private:
  struct State;
  void Render();
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  HWND window_ = nullptr;
  std::unique_ptr<State> state_;
};

// Plays the removal puff centred on `screen` and cleans itself up. Honours the
// system's "Show animations" setting by skipping the animation entirely.
void ShowRemovalPuff(HWND owner, POINT screen);

}  // namespace kelpie::windows
