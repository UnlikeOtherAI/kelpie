#include "external_app_prompt.h"

#include <shellapi.h>
#include <shlwapi.h>

#include "windows_utf.h"

namespace kelpie::windows {
namespace {

bool prompt_open = false;

std::wstring HandlerName(const std::wstring& scheme) {
  wchar_t name[MAX_PATH] = {};
  DWORD size = MAX_PATH;
  if (FAILED(AssocQueryStringW(ASSOCF_IS_PROTOCOL, ASSOCSTR_FRIENDLYAPPNAME, scheme.c_str(), nullptr, name, &size))) {
    return {};
  }
  return name;
}

}  // namespace

void PromptToOpenExternalApp(HWND window, const std::string& requester, const std::string& url) {
  const auto colon = url.find(':');
  const auto wide_url = utf::Utf8ToWide(url);
  if (prompt_open || colon == std::string::npos || !wide_url || !IsWindowVisible(window)) return;
  const std::wstring app = HandlerName(utf::Utf8ToWideDisplay(url.substr(0, colon)));
  if (app.empty()) return;

  const std::wstring title = L"Open “" + app + L"”?";
  const std::wstring message =
      (requester.empty() ? std::wstring(L"This page") : utf::Utf8ToWideDisplay(requester)) + L" wants to open this app.";
  prompt_open = true;
  // The external CEF pump already guards against nested CefDoMessageLoopWork.
  const int answer = MessageBoxW(window, message.c_str(), title.c_str(), MB_OKCANCEL | MB_DEFBUTTON2 | MB_ICONQUESTION);
  prompt_open = false;
  if (answer != IDOK || !IsWindowVisible(window)) return;
  ShellExecuteW(window, L"open", wide_url->c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

}  // namespace kelpie::windows
