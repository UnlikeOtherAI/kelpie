#include "theme/panels.h"

#include <commctrl.h>

#include "theme/paint.h"

namespace kelpie::windows::ui {
namespace {

constexpr int kHeaderHeightDip = 52;
constexpr int kHeaderPaddingDip = 16;
constexpr int kHeaderTextDip = 16;
constexpr int kEmptyStateTextDip = 13;

}  // namespace

void StyleList(HWND list, HFONT font) {
  if (list == nullptr) return;
  // Full-row selection matches the macOS sheets, whose rows are clickable
  // across their whole width rather than on the label text alone.
  ListView_SetExtendedListViewStyle(list, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER |
                                              LVS_EX_LABELTIP);
  SendMessageW(list, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
  const auto colors = Colors();
  ListView_SetBkColor(list, colors.canvas);
  ListView_SetTextBkColor(list, colors.canvas);
  ListView_SetTextColor(list, colors.text);
  ApplyControlAppearance(list);
}

void RefreshPanelFont(HWND owner, HWND control, HFONT* font, int dip_size) {
  if (control == nullptr || font == nullptr) return;
  HFONT next = MakeFont(owner, dip_size, FW_NORMAL);
  if (next == nullptr) return;
  SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(next), TRUE);
  if (*font != nullptr) DeleteObject(*font);
  *font = next;
}

int PanelHeaderHeight(HWND panel) {
  return Dip(panel, kHeaderHeightDip);
}

void PaintPanelHeader(HDC dc, HWND panel, const wchar_t* title) {
  if (dc == nullptr || panel == nullptr) return;
  RECT rect{};
  GetClientRect(panel, &rect);
  const auto colors = Colors();
  FillSolid(dc, rect, colors.canvas);

  RECT header = rect;
  header.bottom = PanelHeaderHeight(panel);
  const RECT text{header.left + Dip(panel, kHeaderPaddingDip), header.top,
                  header.right - Dip(panel, kHeaderPaddingDip), header.bottom};
  DrawLabel(dc, panel, text, title, colors.text, kHeaderTextDip, FW_SEMIBOLD);
}

void PaintEmptyState(HDC dc, HWND panel, const RECT& area, const wchar_t* message) {
  if (dc == nullptr || panel == nullptr || message == nullptr) return;
  DrawLabel(dc, panel, area, message, Colors().muted_text, kEmptyStateTextDip, FW_NORMAL,
            DT_CENTER);
}

}  // namespace kelpie::windows::ui
