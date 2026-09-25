#include "windows_app.h"
#include "windows_utf.h"
#include "../resources/resource.h"
#include <shellapi.h>
#include <shlwapi.h>

namespace kelpie::windows {
namespace {
bool OpenAccountBrowser(const std::string& url) {
  wchar_t executable[32768]{}; DWORD length=32768;
  const auto wide=utf::Utf8ToWideDisplay(url);
  // OAuth must stay outside Kelpie's inspectable renderer even if it is default.
  const bool kelpie=SUCCEEDED(AssocQueryStringW(static_cast<ASSOCF>(0x1000),ASSOCSTR_EXECUTABLE,L"https",nullptr,executable,&length)) &&
      _wcsicmp(PathFindFileNameW(executable),L"kelpie.exe")==0;
  const std::wstring target=kelpie ? L"microsoft-edge:"+wide : wide;
  return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr,L"open",target.c_str(),nullptr,nullptr,SW_SHOWNORMAL))>32;
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
  HMENU menu=CreatePopupMenu();
  AppendMenuW(menu,MF_STRING|MF_DISABLED,0,L"UnlikeOtherAI account");
  if (state.signed_in) {
    AppendMenuW(menu,MF_STRING|MF_DISABLED,0,MenuLabel(state.name.empty()?state.email:state.name).c_str());
    AppendMenuW(menu,MF_STRING|MF_DISABLED,0,L"Showing account favorites");
    AppendMenuW(menu,MF_STRING|(state.busy?MF_DISABLED:0),2,state.busy?L"Syncing favorites...":L"Refresh favorites");
    AppendMenuW(menu,MF_STRING,3,L"Sign out and show local favorites");
  } else if (state.signing_in) {
    AppendMenuW(menu,MF_STRING|MF_DISABLED,0,L"Complete sign-in in your browser");
    AppendMenuW(menu,MF_STRING,3,L"Cancel sign-in");
  } else {
    AppendMenuW(menu,MF_STRING|MF_DISABLED,0,L"Sign in to switch to account favorites");
    AppendMenuW(menu,MF_STRING|(state.busy?MF_DISABLED:0),1,L"Sign in with UOA");
  }
  if (!state.error.empty()) AppendMenuW(menu,MF_STRING|MF_DISABLED,0,MenuLabel(state.error).c_str());
  RECT bounds{}; GetWindowRect(GetDlgItem(shell_->hwnd(),IDC_ACCOUNT_BUTTON),&bounds);
  const auto selected=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTALIGN,bounds.right,bounds.bottom,0,shell_->hwnd(),nullptr);
  DestroyMenu(menu);
  if (selected==1) account_->StartSignIn(config_.profile_dir,OpenAccountBrowser);
  if (selected==2) account_->StartBookmarkAction("refresh");
  if (selected==3) account_->SignOut();
}
}  // namespace kelpie::windows
