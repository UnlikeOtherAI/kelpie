#include "link_list_panel.h"

#include <commctrl.h>

#include <algorithm>
#include <string_view>

#include <nlohmann/json.hpp>

#include "display_format.h"
#include "theme/theme.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {
constexpr int kListId = 100;
}  // namespace

LinkListPanel::Config LinkListPanel::Bookmarks() {
  return {L"KelpieBookmarksView", L"Bookmarks",
          L"No bookmarks yet. Use the star in the address bar to save the page you are on.",
          {{L"Name", "title", 300}, {L"Address", "url", 0}}};
}

LinkListPanel::Config LinkListPanel::History() {
  return {L"KelpieHistoryView", L"History", L"Pages you visit will appear here.",
          {{L"Title", "title", 300}, {L"Address", "url", 0}, {L"Visited", "timestamp", 160}}};
}

PanelWindow::Spec LinkListPanel::Describe() const {
  return {config_.class_name, config_.title, {760, 480}, {420, 240}};
}

void LinkListPanel::CreateControls() {
  list_ = CreateWindowExW(0, WC_LISTVIEWW, L"",
                          WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SINGLESEL |
                              LVS_SHOWSELALWAYS | LVS_OWNERDATA,
                          0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
                          instance_, nullptr);
  int index = 0;
  for (const auto& column : config_.columns) {
    LVCOLUMNW item{};
    item.mask = LVCF_TEXT | LVCF_WIDTH;
    item.pszText = const_cast<wchar_t*>(column.title);
    item.cx = ui::Dip(hwnd_, column.width_dip == 0 ? 200 : column.width_dip);
    ListView_InsertColumn(list_, index++, &item);
  }
  ApplyTheme();
  Populate();
}

void LinkListPanel::ApplyTheme() {
  ui::StyleList(list_, font_);
  for (std::size_t index = 0; index < config_.columns.size(); ++index) {
    const int width = config_.columns[index].width_dip;
    if (width != 0) ListView_SetColumnWidth(list_, static_cast<int>(index), ui::Dip(hwnd_, width));
  }
}

void LinkListPanel::Layout(const RECT& client) {
  if (list_ == nullptr) return;
  SetWindowPos(list_, nullptr, 0, 0, client.right, client.bottom, SWP_NOZORDER);
  // The flexible column takes what the fixed ones leave, so a wider window
  // shows more of each address instead of an empty band on the right.
  int fixed = GetSystemMetrics(SM_CXVSCROLL);
  int flexible = -1;
  for (std::size_t index = 0; index < config_.columns.size(); ++index) {
    if (config_.columns[index].width_dip == 0) flexible = static_cast<int>(index);
    else fixed += ListView_GetColumnWidth(list_, static_cast<int>(index));
  }
  if (flexible >= 0) {
    ListView_SetColumnWidth(list_, flexible, std::max(ui::Dip(hwnd_, 160), static_cast<int>(client.right) - fixed));
  }
}

void LinkListPanel::UpdateFromJson(const std::string& json) {
  rows_.clear();
  const auto parsed = nlohmann::json::parse(json, nullptr, false);
  if (parsed.is_array()) {
    for (const auto& entry : parsed) {
      if (!entry.is_object()) continue;
      Row row;
      row.url = entry.value("url", "");
      for (const auto& column : config_.columns) {
        const std::string value = entry.value(column.field, "");
        row.cells.push_back(std::string_view(column.field) == "timestamp"
                                ? format::LocalTime(value)
                                : utf::Utf8ToWideDisplay(value));
      }
      rows_.push_back(std::move(row));
    }
  }
  Populate();
}

void LinkListPanel::Populate() {
  if (list_ == nullptr) return;
  ListView_SetItemCountEx(list_, static_cast<int>(rows_.size()), 0);
  InvalidateRect(list_, nullptr, TRUE);
}

void LinkListPanel::OpenSelected() {
  const int selected = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
  if (selected < 0 || selected >= static_cast<int>(rows_.size()) || !on_navigate_) return;
  const std::string url = rows_[static_cast<std::size_t>(selected)].url;
  if (url.empty()) return;
  Hide();
  on_navigate_(url);
}

bool LinkListPanel::HandlePanelMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result) {
  if (message == WM_COMMAND && LOWORD(wparam) == IDOK) {
    // Enter in the list reaches the panel as IDOK through IsDialogMessage.
    OpenSelected();
    *result = 0;
    return true;
  }
  if (message != WM_NOTIFY) return false;
  const auto* notice = reinterpret_cast<NMHDR*>(lparam);
  if (notice == nullptr || notice->idFrom != kListId) return false;
  switch (notice->code) {
    case LVN_GETDISPINFOW: {
      auto* info = reinterpret_cast<NMLVDISPINFOW*>(lparam);
      const auto row = static_cast<std::size_t>(info->item.iItem);
      const auto cell = static_cast<std::size_t>(info->item.iSubItem);
      if ((info->item.mask & LVIF_TEXT) != 0 && row < rows_.size() && cell < rows_[row].cells.size()) {
        wcsncpy_s(info->item.pszText, info->item.cchTextMax, rows_[row].cells[cell].c_str(), _TRUNCATE);
      }
      *result = 0;
      return true;
    }
    case LVN_ITEMACTIVATE:
      OpenSelected();
      *result = 0;
      return true;
    case LVN_GETEMPTYMARKUP:
      *result = ui::AnswerEmptyMarkup(lparam, config_.empty_message) ? TRUE : FALSE;
      return true;
    default:
      return false;
  }
}

}  // namespace kelpie::windows
