#include "network_inspector.h"

#include <commctrl.h>

#include <algorithm>
#include <array>
#include <string>

#include <nlohmann/json.hpp>

#include "../resources/resource.h"

namespace kelpie::windows {
namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  std::wstring output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), L'\0');
  if (size > 1) {
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1);
  }
  return output;
}

void AddComboItem(HWND combo, const wchar_t* value) {
  SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(value));
}

std::wstring ValueOrAll(HWND combo) {
  const int index = static_cast<int>(SendMessageW(combo, CB_GETCURSEL, 0, 0));
  if (index == CB_ERR) {
    return L"All";
  }
  wchar_t buffer[32]{};
  SendMessageW(combo, CB_GETLBTEXT, static_cast<WPARAM>(index), reinterpret_cast<LPARAM>(buffer));
  return buffer;
}

}  // namespace

bool NetworkInspector::EnsureCreated(HINSTANCE instance, HWND owner) {
  if (hwnd_ != nullptr) {
    return true;
  }
  instance_ = instance;
  owner_ = owner;

  WNDCLASSW window_class{};
  window_class.lpfnWndProc = &NetworkInspector::WindowProc;
  window_class.hInstance = instance_;
  window_class.lpszClassName = L"KelpieNetworkInspector";
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);

  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW, window_class.lpszClassName, L"Network Inspector",
                          WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT,
                          980, 540, owner_, nullptr, instance_, this);
  return hwnd_ != nullptr;
}

void NetworkInspector::ToggleVisible() {
  if (hwnd_ == nullptr) {
    return;
  }
  const bool visible = IsWindowVisible(hwnd_) != FALSE;
  ShowWindow(hwnd_, visible ? SW_HIDE : SW_SHOW);
  if (!visible) {
    SetForegroundWindow(hwnd_);
    ApplyFilter();
  }
}

void NetworkInspector::UpdateFromJson(const std::string& network_json) {
  network_json_ = network_json;
  ApplyFilter();
}

LRESULT CALLBACK NetworkInspector::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<NetworkInspector*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = reinterpret_cast<NetworkInspector*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  }
  return self != nullptr ? self->HandleMessage(message, wparam, lparam)
                         : DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT NetworkInspector::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE:
      CreateControls();
      return 0;
    case WM_SIZE:
      Resize();
      return 0;
    case WM_COMMAND:
      if (HIWORD(wparam) == CBN_SELCHANGE) {
        ApplyFilter();
      }
      return 0;
    default:
      return DefWindowProcW(hwnd_, message, wparam, lparam);
  }
}

void NetworkInspector::CreateControls() {
  method_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
                                  0, 0, 120, 200, hwnd_, reinterpret_cast<HMENU>(IDC_NETWORK_METHOD),
                                  instance_, nullptr);
  type_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
                                0, 0, 120, 200, hwnd_, reinterpret_cast<HMENU>(IDC_NETWORK_TYPE),
                                instance_, nullptr);
  source_combo_ = CreateWindowExW(0, WC_COMBOBOXW, L"", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
                                  0, 0, 120, 200, hwnd_, reinterpret_cast<HMENU>(IDC_NETWORK_SOURCE),
                                  instance_, nullptr);
  list_view_ = CreateWindowExW(WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
                               WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL,
                               0, 0, 100, 100, hwnd_, reinterpret_cast<HMENU>(IDC_NETWORK_LIST),
                               instance_, nullptr);

  PopulateFilters();
  ListView_SetExtendedListViewStyle(list_view_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);

  const std::array<std::pair<const wchar_t*, int>, 6> columns{{
      {L"Method", 80},
      {L"URL", 420},
      {L"Status", 70},
      {L"Type", 90},
      {L"Size", 80},
      {L"Time", 90},
  }};
  int index = 0;
  for (const auto& [title, width] : columns) {
    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH;
    column.pszText = const_cast<wchar_t*>(title);
    column.cx = width;
    ListView_InsertColumn(list_view_, index++, &column);
  }

  ApplyFilter();
}

void NetworkInspector::Resize() {
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  const int top = 12;
  SetWindowPos(method_combo_, nullptr, 12, top, 140, 200, SWP_NOZORDER);
  SetWindowPos(type_combo_, nullptr, 164, top, 140, 200, SWP_NOZORDER);
  SetWindowPos(source_combo_, nullptr, 316, top, 140, 200, SWP_NOZORDER);
  SetWindowPos(list_view_, nullptr, 12, top + 36, rect.right - 24, rect.bottom - top - 48,
               SWP_NOZORDER);
}

void NetworkInspector::PopulateFilters() const {
  for (const wchar_t* method : {L"All", L"GET", L"POST", L"PUT", L"DELETE"}) {
    AddComboItem(method_combo_, method);
  }
  for (const wchar_t* type : {L"All", L"HTML", L"JSON", L"JS", L"CSS", L"Image", L"Font", L"XML", L"Other"}) {
    AddComboItem(type_combo_, type);
  }
  for (const wchar_t* source : {L"All", L"Browser", L"JS"}) {
    AddComboItem(source_combo_, source);
  }
  SendMessageW(method_combo_, CB_SETCURSEL, 0, 0);
  SendMessageW(type_combo_, CB_SETCURSEL, 0, 0);
  SendMessageW(source_combo_, CB_SETCURSEL, 0, 0);
}

void NetworkInspector::ApplyFilter() {
  if (list_view_ == nullptr) {
    return;
  }
  ListView_DeleteAllItems(list_view_);

  const std::wstring method = ValueOrAll(method_combo_);
  const std::wstring type = ValueOrAll(type_combo_);
  const std::wstring source = ValueOrAll(source_combo_);

  const auto parsed = nlohmann::json::parse(network_json_, nullptr, false);
  if (!parsed.is_array()) {
    return;
  }

  int row = 0;
  for (const auto& entry : parsed) {
    if (!entry.is_object()) {
      continue;
    }
    const std::wstring entry_method = Utf8ToWide(entry.value("method", ""));
    const std::wstring entry_type = Utf8ToWide(entry.value("category", entry.value("content_type", "")));
    std::wstring initiator = Utf8ToWide(entry.value("initiator", "browser"));
    std::transform(initiator.begin(), initiator.end(), initiator.begin(), ::towupper);

    if (method != L"All" && entry_method != method) {
      continue;
    }
    if (type != L"All" && entry_type != type) {
      continue;
    }
    if (source != L"All" && initiator != source) {
      continue;
    }

    std::wstring url = Utf8ToWide(entry.value("url", ""));
    std::wstring status = std::to_wstring(entry.value("status_code", 0));
    std::wstring size = std::to_wstring(entry.value("size", 0));
    std::wstring time = std::to_wstring(entry.value("duration", 0)) + L" ms";

    LVITEMW item{};
    item.mask = LVIF_TEXT;
    item.iItem = row;
    item.pszText = const_cast<LPWSTR>(entry_method.c_str());
    ListView_InsertItem(list_view_, &item);
    ListView_SetItemText(list_view_, row, 1, const_cast<LPWSTR>(url.c_str()));
    ListView_SetItemText(list_view_, row, 2, const_cast<LPWSTR>(status.c_str()));
    ListView_SetItemText(list_view_, row, 3, const_cast<LPWSTR>(entry_type.c_str()));
    ListView_SetItemText(list_view_, row, 4, const_cast<LPWSTR>(size.c_str()));
    ListView_SetItemText(list_view_, row, 5, const_cast<LPWSTR>(time.c_str()));
    ++row;
  }
}

}  // namespace kelpie::windows
