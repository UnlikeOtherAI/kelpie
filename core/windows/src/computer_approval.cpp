#include "computer_approval.h"
#include "windows_utf.h"
#include <vector>

namespace kelpie::windows {
void PollComputerApproval(PeerApprovalQueue& approvals, HWND owner) {
  // MessageBox pumps the owner timer; a nested Tick must not open another gate.
  static bool presenting = false;
  if (presenting) return;
  approvals.SetAvailable(IsWindowVisible(owner));
  const auto request = approvals.Pending();
  if (request.is_null() || !IsWindowVisible(owner)) return;
  presenting = true;
  struct Reset { bool& value; ~Reset() { value = false; } } reset{presenting};
  const auto message = utf::Utf8ToWideDisplay(request.at("sourceAddress").get<std::string>() +
      "\n\nComputer key: " + request.at("publicKey").get<std::string>() + "\n\nName (self-reported): " + request.at("clientName").get<std::string>() +
      "\n\nAllow this computer to control Kelpie, even when its IP changes? This stays allowed until you revoke it in Settings.");
  const auto id = request.at("requestId").get<std::string>();
  if (MessageBoxW(owner, message.c_str(), L"Allow this computer?", MB_YESNO | MB_DEFBUTTON2 | MB_ICONQUESTION) == IDYES) {
    if (!approvals.Approve(id)) MessageBoxW(owner, L"Could not save approval, or the request expired. Try again.", L"Computer approval", MB_OK | MB_ICONERROR);
  } else approvals.Deny(id);
}

namespace {
struct ComputerList {
  PeerTrustStore store;
  HWND list = nullptr;
  std::vector<std::string> addresses;
  bool done = false;
  void Refresh() {
    SendMessageW(list, LB_RESETCONTENT, 0, 0);
    addresses.clear();
    for (const auto& computer : store.List()) {
      const std::string address = computer.at("publicKey");
      addresses.push_back(address);
      const auto label = utf::Utf8ToWideDisplay(address + "  " + computer.at("name").get<std::string>());
      SendMessageW(list, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(label.c_str()));
    }
  }
};

LRESULT CALLBACK ComputersProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* state = reinterpret_cast<ComputerList*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    state = static_cast<ComputerList*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
  }
  if (message == WM_CREATE) {
    CreateWindowW(L"STATIC", L"Localhost is always allowed. Select a computer to revoke.", WS_CHILD | WS_VISIBLE,
        16, 16, 480, 24, hwnd, nullptr, nullptr, nullptr);
    state->list = CreateWindowExW(WS_EX_CLIENTEDGE, L"LISTBOX", L"", WS_CHILD | WS_VISIBLE | WS_VSCROLL | LBS_NOTIFY,
        16, 48, 480, 240, hwnd, nullptr, nullptr, nullptr);
    CreateWindowW(L"BUTTON", L"Revoke", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        304, 304, 88, 30, hwnd, reinterpret_cast<HMENU>(1001), nullptr, nullptr);
    CreateWindowW(L"BUTTON", L"Close", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        408, 304, 88, 30, hwnd, reinterpret_cast<HMENU>(IDCANCEL), nullptr, nullptr);
    try { state->Refresh(); } catch (...) { MessageBoxW(hwnd, L"Could not read trusted computers.", L"Storage error", MB_OK | MB_ICONERROR); }
    return 0;
  }
  if (message == WM_COMMAND && LOWORD(wparam) == 1001) {
    const auto index = SendMessageW(state->list, LB_GETCURSEL, 0, 0);
    if (index != LB_ERR && static_cast<std::size_t>(index) < state->addresses.size()) {
      try { state->store.Revoke(state->addresses[index]); state->Refresh(); }
      catch (...) { MessageBoxW(hwnd, L"Could not revoke this computer.", L"Storage error", MB_OK | MB_ICONERROR); }
    }
    return 0;
  }
  if (message == WM_CLOSE || (message == WM_COMMAND && LOWORD(wparam) == IDCANCEL)) {
    state->done = true; DestroyWindow(hwnd); return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
}

void ShowTrustedComputers(HWND owner) {
  const auto instance = GetModuleHandleW(nullptr);
  WNDCLASSW window{};
  window.lpfnWndProc = ComputersProc; window.hInstance = instance;
  window.lpszClassName = L"KelpieTrustedComputers";
  window.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  RegisterClassW(&window);
  ComputerList state;
  HWND dialog = CreateWindowExW(WS_EX_DLGMODALFRAME, window.lpszClassName, L"Trusted computers",
      WS_POPUP | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 528, 390, owner, nullptr, instance, &state);
  if (!dialog) return;
  EnableWindow(owner, FALSE); ShowWindow(dialog, SW_SHOW);
  MSG message{};
  while (!state.done && GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (!IsDialogMessageW(dialog, &message)) { TranslateMessage(&message); DispatchMessageW(&message); }
  }
  EnableWindow(owner, TRUE); SetActiveWindow(owner);
}
}  // namespace kelpie::windows
