#include "inference_view.h"
#include "windows_utf.h"
#include <commdlg.h>
#include <future>
#include <vector>

namespace kelpie::windows {
namespace {
using json = nlohmann::json;
enum Control { List = 3200, Name, URL, Key, Model, Save, Models, Test, Use, Remove, New,
               File, Browse, Load, Unload, Prompt, Ask, Stop, Result, Page };
std::string Text(HWND window, int id) {
  HWND control = GetDlgItem(window, id);
  std::wstring value(GetWindowTextLengthW(control) + 1, L'\0');
  value.resize(GetWindowTextW(control, value.data(), value.size()));
  return utf::WideToUtf8(value).value_or("");
}
void Set(HWND window, int id, const std::string& value) {
  SetWindowTextW(GetDlgItem(window, id), utf::Utf8ToWideDisplay(value).c_str());
}
struct State {
  InferenceService& service;
  HWND window = nullptr;
  json endpoints = json::array();
  std::string id;
  std::string operation;
  std::future<json> pending;
  bool closing = false;
  bool done = false;

  void Reload() {
    auto result = service.Execute("ai-endpoints");
    endpoints = result.value("endpoints", json::array());
    auto list = GetDlgItem(window, List);
    SendMessageW(list, CB_RESETCONTENT, 0, 0);
    for (const auto& endpoint : endpoints) {
      auto label = utf::Utf8ToWideDisplay(endpoint.value("name", ""));
      auto index = SendMessageW(list, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(label.c_str()));
      if (endpoint.value("id", "") == id) SendMessageW(list, CB_SETCURSEL, index, 0);
    }
  }
  void Select() {
    auto index = SendMessageW(GetDlgItem(window, List), CB_GETCURSEL, 0, 0);
    if (index < 0 || index >= static_cast<LRESULT>(endpoints.size())) return;
    const auto& endpoint = endpoints[index];
    id = endpoint.value("id", "");
    Set(window, Name, endpoint.value("name", "")); Set(window, URL, endpoint.value("baseURL", ""));
    Set(window, Model, endpoint.value("model", "")); Set(window, Key, "");
  }
  void Start(std::string method, json body = json::object()) {
    if (pending.valid()) return;
    operation = method;
    for (int control : {List, Name, URL, Key, Model, Save, Models, Test, Use, Remove, New, Browse, Load, Unload, Ask})
      EnableWindow(GetDlgItem(window, control), FALSE);
    Set(window, Result, "Working…");
    pending = std::async(std::launch::async, [this, method, body] { return service.Execute(method, body); });
    SetTimer(window, 1, 100, nullptr);
  }
  void Complete() {
    if (!pending.valid() || pending.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
    auto result = pending.get(); KillTimer(window, 1);
    if (closing) { DestroyWindow(window); done = true; return; }
    for (int control : {List, Name, URL, Key, Model, Save, Models, Test, Use, Remove, New, Browse, Load, Unload, Ask})
      EnableWindow(GetDlgItem(window, control), TRUE);
    if (result.contains("endpoint")) id = result["endpoint"].value("id", id);
    if (operation == "ai-endpoint-models" && result.value("success", false)) {
      auto model = GetDlgItem(window, Model); auto selected = Text(window, Model);
      SendMessageW(model, CB_RESETCONTENT, 0, 0);
      for (const auto& entry : result["models"]) {
        auto value = utf::Utf8ToWideDisplay(entry.value("id", ""));
        SendMessageW(model, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(value.c_str()));
      }
      Set(window, Model, selected);
    }
    std::string message;
    if (!result.value("success", false)) message = result.value("error", json::object()).value("message", "Operation failed");
    else if (result.contains("response")) message = result.value("response", "");
    else if (operation == "ai-endpoint-test") message = "Server test: " + result.at("health").value("state", "unknown");
    else if (operation == "ai-load") message = "Model selected and ready";
    else if (operation == "ai-unload") message = "Model unloaded";
    else if (operation == "ai-endpoint-save") { message = "Endpoint saved"; Set(window, Key, ""); }
    else if (operation == "ai-endpoint-remove") { message = "Endpoint removed"; id.clear(); }
    else message = "Model list refreshed";
    Set(window, Result, message); Reload();
  }
};
HWND Add(HWND parent, int id, const wchar_t* kind, const wchar_t* text, int x, int y, int w, int h, DWORD style = 0) {
  auto control = CreateWindowExW(kind == std::wstring(L"EDIT") ? WS_EX_CLIENTEDGE : 0, kind, text,
      WS_CHILD | WS_VISIBLE | WS_TABSTOP | style, x, y, w, h, parent,
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
  SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  return control;
}
void CreateControls(HWND window) {
  Add(window, 0, L"STATIC", L"Inference endpoints — localhost means this Windows computer", 16, 12, 670, 20);
  Add(window, List, L"COMBOBOX", L"", 16, 36, 540, 240, CBS_DROPDOWNLIST | WS_VSCROLL);
  Add(window, New, L"BUTTON", L"New", 570, 36, 100, 25);
  const wchar_t* labels[] = {L"Name", L"Base URL", L"API key", L"Model"};
  for (int index = 0; index < 4; ++index) {
    Add(window, 0, L"STATIC", labels[index], 16, 75 + index * 34, 90, 24);
    Add(window, Name + index, index == 3 ? L"COMBOBOX" : L"EDIT", index == 0 ? L"This computer" :
        index == 1 ? L"http://127.0.0.1:11434/v1" : L"", 110, 72 + index * 34, 560, index == 3 ? 220 : 25,
        index == 3 ? CBS_DROPDOWN | WS_VSCROLL : ES_AUTOHSCROLL | (index == 2 ? ES_PASSWORD : 0));
  }
  Add(window, 0, L"STATIC", L"Leave API key blank to keep it. Keys are encrypted for your Windows account.", 110, 207, 570, 24);
  const wchar_t* buttons[] = {L"Save", L"Refresh models", L"Test", L"Use", L"Remove"};
  for (int index = 0; index < 5; ++index) Add(window, Save + index, L"BUTTON", buttons[index], 16 + index * 132, 238, 124, 28);
  Add(window, 0, L"STATIC", L"On-device GGUF — offline text inference", 16, 283, 650, 24);
  Add(window, File, L"EDIT", L"", 16, 313, 530, 25, ES_READONLY | ES_AUTOHSCROLL);
  Add(window, Browse, L"BUTTON", L"Choose GGUF", 552, 313, 118, 25);
  Add(window, Load, L"BUTTON", L"Load on device", 16, 348, 160, 28);
  Add(window, Unload, L"BUTTON", L"Unload model", 190, 348, 140, 28);
  Add(window, 0, L"STATIC", L"Ask the selected model", 16, 392, 650, 24);
  Add(window, Prompt, L"EDIT", L"", 16, 420, 654, 68, ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN | WS_VSCROLL);
  Add(window, Ask, L"BUTTON", L"Ask", 16, 500, 100, 28);
  Add(window, Stop, L"BUTTON", L"Cancel request", 125, 500, 130, 28);
  Add(window, Page, L"BUTTON", L"Include current page text", 275, 500, 300, 28, BS_AUTOCHECKBOX);
  Add(window, Result, L"EDIT", L"Select a local GGUF or save, test and use an endpoint.", 16, 540, 654, 100,
      ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY | WS_VSCROLL);
}
LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  auto* state = reinterpret_cast<State*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    state = static_cast<State*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
    state->window = window; SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
  }
  if (!state) return DefWindowProcW(window, message, wp, lp);
  if (message == WM_CREATE) { CreateControls(window); state->Reload(); return 0; }
  if (message == WM_TIMER) { state->Complete(); return 0; }
  if (message == WM_CLOSE) {
    if (state->pending.valid()) { state->closing = true; state->service.Cancel(); }
    else { DestroyWindow(window); state->done = true; }
    return 0;
  }
  if (message == WM_COMMAND) {
    const auto id = LOWORD(wp);
    if (id == List && HIWORD(wp) == CBN_SELCHANGE) { state->Select(); return 0; }
    if (HIWORD(wp) != BN_CLICKED) return DefWindowProcW(window, message, wp, lp);
    if (id == Stop) { state->service.Cancel(); return 0; }
    if (state->pending.valid()) return 0;
    if (id == New) { state->id.clear(); Set(window, Name, ""); Set(window, Key, ""); Set(window, Model, ""); return 0; }
    if (id == Browse) {
      wchar_t path[32768]{}; OPENFILENAMEW picker{}; picker.lStructSize = sizeof(picker); picker.hwndOwner = window;
      picker.lpstrFilter = L"GGUF model\0*.gguf\0"; picker.lpstrFile = path; picker.nMaxFile = 32768;
      picker.Flags = OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;
      if (GetOpenFileNameW(&picker)) SetWindowTextW(GetDlgItem(window, File), path);
      return 0;
    }
    if (id == Load) state->Start("ai-load", {{"backend", "native"}, {"model", Text(window, File)}});
    if (id == Unload) state->Start("ai-unload");
    if (id == Save) {
      json body = {{"name", Text(window, Name)}, {"baseURL", Text(window, URL)}, {"model", Text(window, Model)}};
      if (!state->id.empty()) body["id"] = state->id;
      if (!Text(window, Key).empty()) body["apiKey"] = Text(window, Key);
      state->Start("ai-endpoint-save", body);
    }
    if (id == Models) state->Start("ai-endpoint-models", {{"id", state->id}});
    if (id == Test) state->Start("ai-endpoint-test", {{"id", state->id}, {"model", Text(window, Model)}});
    if (id == Use) state->Start("ai-load", {{"backend", "openai"}, {"endpoint", state->id}, {"model", Text(window, Model)}});
    if (id == Remove) state->Start("ai-endpoint-remove", {{"id", state->id}});
    if (id == Ask) {
      json body = {{"prompt", Text(window, Prompt)}, {"agent", false}};
      if (SendMessageW(GetDlgItem(window, Page), BM_GETCHECK, 0, 0) == BST_CHECKED) body["context"] = "page_text";
      state->Start("ai-infer", body);
    }
    return 0;
  }
  return DefWindowProcW(window, message, wp, lp);
}
}
void ShowInferenceSettings(HINSTANCE instance, HWND owner, InferenceService& service) {
  WNDCLASSW klass{}; klass.lpfnWndProc = Procedure; klass.hInstance = instance;
  klass.lpszClassName = L"KelpieInference"; klass.hbrBackground = GetSysColorBrush(COLOR_BTNFACE);
  klass.hCursor = LoadCursorW(nullptr, IDC_ARROW); RegisterClassW(&klass);
  State state{service};
  auto window = CreateWindowExW(WS_EX_DLGMODALFRAME, klass.lpszClassName, L"Local AI", WS_CAPTION | WS_SYSMENU,
      CW_USEDEFAULT, CW_USEDEFAULT, 706, 690, owner, nullptr, instance, &state);
  if (!window) return;
  EnableWindow(owner, FALSE); ShowWindow(window, SW_SHOW);
  MSG message{};
  while (!state.done && GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (!IsDialogMessageW(window, &message)) { TranslateMessage(&message); DispatchMessageW(&message); }
  }
  EnableWindow(owner, TRUE); SetForegroundWindow(owner);
}
}
