#pragma once

#include <commctrl.h>

#include "ui_theme.h"

namespace kelpie::windows::ui {

inline void StyleList(HWND list, HFONT font) {
  ListView_SetExtendedListViewStyle(list, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
  SendMessageW(list, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  ListView_SetBkColor(list, Colors().canvas);
  ListView_SetTextBkColor(list, Colors().canvas);
  ListView_SetTextColor(list, Colors().text);
}

inline void RefreshPanelFont(HWND owner, HWND control, HFONT* font, int dip_size = 13) {
  HFONT next = MakeFont(owner, dip_size, FW_NORMAL);
  SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(next), TRUE);
  if (*font != nullptr) DeleteObject(*font);
  *font = next;
}

inline void PaintPanelHeader(HDC dc, HWND panel, const wchar_t* title) {
  RECT rect{};
  GetClientRect(panel, &rect);
  const auto colors = Colors();
  HBRUSH brush = CreateSolidBrush(colors.canvas);
  FillRect(dc, &rect, brush);
  DeleteObject(brush);
  rect.bottom = Dip(panel, 52);
  HFONT font = MakeFont(panel, 16, FW_SEMIBOLD);
  HGDIOBJ old = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, colors.text);
  RECT text{Dip(panel, 16), 0, rect.right - Dip(panel, 16), rect.bottom};
  DrawTextW(dc, title, -1, &text, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  SelectObject(dc, old);
  DeleteObject(font);
}

}  // namespace kelpie::windows::ui
