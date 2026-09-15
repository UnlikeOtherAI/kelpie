#include "bookmarks_view.h"

#include <commctrl.h>

#include <nlohmann/json.hpp>

#include "../resources/resource.h"
#include "windows_utf.h"

namespace kelpie::windows {

bool BookmarksView::EnsureCreated(HINSTANCE instance, HWND owner) {
  if (hwnd_ != nullptr) {
    return true;
  }
  instance_ = instance;
  owner_ = owner;

  WNDCLASSW window_class{};
  window_class.lpfnWndProc = &BookmarksView::WindowProc;
  window_class.hInstance = instance_;
  window_class.lpszClassName = L"KelpieBookmarksView";
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);

  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW, window_class.lpszClassName, L"Bookmarks",
                          WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT,
                          720, 420, owner_, nullptr, instance_, this);
  return hwnd_ != nullptr;
}

void BookmarksView::ToggleVisible() {
  if (hwnd_ == nullptr) {
    return;
  }
  const bool visible = IsWindowVisible(hwnd_) != FALSE;
  ShowWindow(hwnd_, visible ? SW_HIDE : SW_SHOW);
  if (!visible) {
    SetForegroundWindow(hwnd_);
  }
}

void BookmarksView::UpdateFromJson(const std::string& bookmarks_json) {
  bookmarks_json_ = bookmarks_json;
  Populate();
}

void BookmarksView::SetNavigateCallback(std::function<void(const std::string&)> callback) {
  on_navigate_ = std::move(callback);
}

LRESULT CALLBACK BookmarksView::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<BookmarksView*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = reinterpret_cast<BookmarksView*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  }
  return self != nullptr ? self->HandleMessage(message, wparam, lparam)
                         : DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT BookmarksView::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE:
      CreateListView();
      return 0;
    case WM_SIZE:
      Resize();
      return 0;
    case WM_NOTIFY: {
      const auto* notification = reinterpret_cast<NMHDR*>(lparam);
      if (notification->idFrom == IDC_BOOKMARKS_LIST && notification->code == NM_DBLCLK && on_navigate_) {
        const int selected = ListView_GetNextItem(list_view_, -1, LVNI_SELECTED);
        wchar_t url[4096]{};
        if (selected >= 0 && ListView_GetItemText(list_view_, selected, 1, url, static_cast<int>(sizeof(url) / sizeof(*url))) > 0) {
          if (const auto utf8 = utf::WideToUtf8(url)) on_navigate_(*utf8);
        }
      }
      return 0;
    }
    default:
      return DefWindowProcW(hwnd_, message, wparam, lparam);
  }
}

void BookmarksView::CreateListView() {
  list_view_ = CreateWindowExW(WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
                               WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL,
                               0, 0, 100, 100, hwnd_, reinterpret_cast<HMENU>(IDC_BOOKMARKS_LIST),
                               instance_, nullptr);
  ListView_SetExtendedListViewStyle(list_view_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);

  LVCOLUMNW column{};
  column.mask = LVCF_TEXT | LVCF_WIDTH;
  column.pszText = const_cast<wchar_t*>(L"Title");
  column.cx = 220;
  ListView_InsertColumn(list_view_, 0, &column);
  column.pszText = const_cast<wchar_t*>(L"URL");
  column.cx = 460;
  ListView_InsertColumn(list_view_, 1, &column);
  Populate();
}

void BookmarksView::Resize() {
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  SetWindowPos(list_view_, nullptr, 0, 0, rect.right, rect.bottom, SWP_NOZORDER);
}

void BookmarksView::Populate() {
  if (list_view_ == nullptr) {
    return;
  }
  ListView_DeleteAllItems(list_view_);

  const auto parsed = nlohmann::json::parse(bookmarks_json_, nullptr, false);
  if (!parsed.is_array()) {
    return;
  }

  int row = 0;
  for (const auto& entry : parsed) {
    if (!entry.is_object()) {
      continue;
    }
    LVITEMW item{};
    item.mask = LVIF_TEXT;
    item.iItem = row;
    std::wstring title = utf::Utf8ToWideDisplay(entry.value("title", ""));
    std::wstring url = utf::Utf8ToWideDisplay(entry.value("url", ""));
    item.pszText = title.data();
    ListView_InsertItem(list_view_, &item);
    ListView_SetItemText(list_view_, row, 1, url.data());
    ++row;
  }
}

}  // namespace kelpie::windows
