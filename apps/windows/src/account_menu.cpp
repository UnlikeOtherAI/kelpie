#include "windows_app.h"
#include "windows_utf.h"
#include "../resources/resource.h"
#include "kelpie/private_login_window.h"
#include <shellapi.h>
#include <shlwapi.h>

namespace kelpie::windows {
namespace {
bool OpenAccountBrowser(const std::string& url) {
  wchar_t executable[32768]{}; DWORD length=32768;
  const auto wide=utf::Utf8ToWideDisplay(url);
  if (FAILED(AssocQueryStringW(static_cast<ASSOCF>(0x1000),ASSOCSTR_EXECUTABLE,L"https",nullptr,executable,&length))) return false;
  wchar_t self[32768]{}; GetModuleFileNameW(nullptr,self,32768);
  if (_wcsicmp(executable,self)==0 || _wcsicmp(PathFindFileNameW(executable),L"kelpie.exe")==0) return false;
  return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr,L"open",wide.c_str(),nullptr,nullptr,SW_SHOWNORMAL))>32;
}
std::wstring MenuLabel(const std::string& text) {
  std::wstring result;
  for (auto c:utf::Utf8ToWideDisplay(text)) { result+=c; if (c==L'&') result+=c; }
  return result;
}
}
void WindowsApp::OnAccountRequested() {
  if (!account_) return;
  const auto state=account_->State();
  if (!state.signed_in && !state.signing_in) {
    if (!account_->StartSignIn(config_.profile_dir,[this](const std::string& url) {
      return OpenAccountBrowser(url) || OpenPrivateLoginWindow(url,[this] { if (account_) account_->SignOut(); });
    })) MessageBeep(MB_OK);
    return;
  }
  HMENU menu=CreatePopupMenu();
  AppendMenuW(menu,MF_STRING|MF_DISABLED,0,L"Account");
  if (state.signed_in) {
    AppendMenuW(menu,MF_STRING|MF_DISABLED,0,MenuLabel(state.name.empty()?state.email:state.name).c_str());
    AppendMenuW(menu,MF_STRING|(state.busy?MF_DISABLED:0),2,state.busy?L"Syncing favorites...":L"Refresh favorites");
    AppendMenuW(menu,MF_STRING,3,L"Sign out");
  } else if (state.signing_in) {
    AppendMenuW(menu,MF_STRING|MF_DISABLED,0,L"Complete login/register");
    AppendMenuW(menu,MF_STRING,3,L"Cancel sign-in");
  }
  if (!state.error.empty()) AppendMenuW(menu,MF_STRING|MF_DISABLED,0,MenuLabel(state.error).c_str());
  RECT bounds{}; GetWindowRect(GetDlgItem(shell_->hwnd(),IDC_ACCOUNT_BUTTON),&bounds);
  const auto selected=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTALIGN,bounds.right,bounds.bottom,0,shell_->hwnd(),nullptr);
  DestroyMenu(menu);
  if (selected==2) account_->StartBookmarkAction("refresh");
  if (selected==3) account_->SignOut();
}
}  // namespace kelpie::windows
