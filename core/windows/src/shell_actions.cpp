#include "windows_app.h"

namespace kelpie::windows {

void WindowsApp::OnHomeRequested() {
  std::string home;
  { std::lock_guard<std::mutex> lock(shell_state_mutex_); home = home_url_; }
  OnNavigateRequested(home.empty() ? "kelpie://start" : home);
}

void WindowsApp::OnAddFavoriteRequested() {
  if (!desktop_app_ || browser_state_.url.empty() || browser_state_.url.rfind("kelpie:",0)==0) return;
  const auto entries = json::parse(GetBookmarksJson(), nullptr, false);
  if (entries.is_array()) for (const auto& item : entries)
    if (item.value("url", "") == browser_state_.url) { shell_->ShowToast(L"Already in favorites"); return; }
  if (account_ && !account_->State().signed_in) {
    account_->BookmarkAction("add", {{"url",browser_state_.url},{"title",browser_state_.title.empty()?browser_state_.url:browser_state_.title}});
    SaveStores();
    shell_->UpdateBrowserState(browser_state_);
    shell_->ShowToast(L"Added to favorites");
    return;
  }
  if (!account_ || !account_->StartBookmarkAction("add", {{"title", browser_state_.title.empty() ? browser_state_.url : browser_state_.title},
                                                        {"url", browser_state_.url}})) {
    shell_->ShowToast(L"Favorites are syncing. Please try again shortly.");
    return;
  }

}

}  // namespace kelpie::windows
