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
// they read as one product rather than four separate dialogs.

// Applies the palette, full-row selection and the dark scrollbar theme to a
// ListView. Full-row hit targets mirror the macOS sheets, whose rows are
// clickable across their whole width rather than on the label alone.
void StyleList(HWND list, HFONT font);

// Replaces a control's font after a DPI or theme change, deleting the old one.
void RefreshPanelFont(HWND owner, HWND control, HFONT* font, int dip_size = 13);

// Paints a panel's background and its title in the shared header hierarchy.
void PaintPanelHeader(HDC dc, HWND panel, const wchar_t* title);

// Height of that header band, in physical pixels for `panel`.
int PanelHeaderHeight(HWND panel);

// Centred placeholder for a panel with nothing to show, so an empty list is
// never a blank rectangle.
void PaintEmptyState(HDC dc, HWND panel, const RECT& area, const wchar_t* message);

}  // namespace kelpie::windows::ui
