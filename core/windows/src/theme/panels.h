#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows::ui {

// Shared chrome for the bookmarks, history, network and settings surfaces, so
// they read as one product rather than four separate dialogs, and open where
// the person is looking.

// Applies the palette, full-row selection and the dark scrollbar theme to a
// ListView. Full-row hit targets mirror the macOS sheets, whose rows are
// clickable across their whole width rather than on the label alone.
void StyleList(HWND list, HFONT font);

// Answers LVN_GETEMPTYMARKUP so an empty list explains itself instead of
// showing a blank rectangle. Return the result from the WM_NOTIFY handler.
bool AnswerEmptyMarkup(LPARAM lparam, const wchar_t* message);

// A `size` rectangle centred over `owner` and kept inside `work_area`. A window
// larger than the work area is shrunk to it, so its caption and its buttons
// can never open off-screen.
RECT CenteredWindowRect(const RECT& owner, const RECT& work_area, SIZE size);

// Screen rectangle for a window owned by `owner` whose client area is
// `client_dip` device-independent pixels at the owner's DPI. It is centred over
// the owner on the owner's monitor, so a pop-up opens where the person is
// looking instead of wherever Windows would cascade it. Pass the rectangle to
// CreateWindowEx so the window is born on that monitor at that DPI.
RECT OwnedWindowRect(HWND owner, SIZE client_dip, DWORD style, DWORD ex_style);

// Outer size of a window with this style whose client area is `client_dip`
// at `window`'s DPI. Used for WM_GETMINMAXINFO minimums.
SIZE OuterSizeForClient(HWND window, SIZE client_dip, DWORD style, DWORD ex_style);

// Applies the rectangle Windows suggests in WM_DPICHANGED.
void ApplySuggestedDpiRect(HWND window, LPARAM lparam);

}  // namespace kelpie::windows::ui
