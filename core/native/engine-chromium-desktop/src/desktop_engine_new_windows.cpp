#include "desktop_cef_client.h"

#include "include/cef_task.h"
#include "new_window_policy.h"

#if defined(_WIN32)
#include <windows.h>
#endif

#include <functional>
#include <utility>

namespace kelpie {
namespace {

class PromptTask final : public CefTask {
 public:
  explicit PromptTask(std::function<void()> body) : body_(std::move(body)) {}
  void Execute() override { body_(); }

 private:
  std::function<void()> body_;
  IMPLEMENT_REFCOUNTING(PromptTask);
};

}  // namespace

bool DesktopCefClient::OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                                      CefRefPtr<CefFrame> frame,
                                      CefRefPtr<CefRequest> request,
                                      bool user_gesture,
                                      bool) {
  const std::string url = request->GetURL().ToString();
  if (!IsAppLink(url)) return false;
  // Chromium never loads an app link itself. Only the page (its main frame or
  // a frame of the same origin) may ask; with a gesture it may always ask,
  // otherwise once per document.
  const std::string requester = OriginOf(frame->GetURL().ToString());
  bool from_page = frame->IsMain();
  if (!from_page && !requester.empty()) {
    const auto main = browser->GetMainFrame();
    from_page = main && OriginOf(main->GetURL().ToString()) == requester;
  }
  if (!from_page || IsDeniedAppLink(url) || !owner_->config.external_app_prompt) return true;
  const int id = browser->GetIdentifier();
  if (!user_gesture && !app_link_asked_.insert(id).second) return true;
  if (opener_ == 0) {
    const auto* tab = owner_->FindTab(browser);
    if (!tab || tab->closing || !owner_->browser || !owner_->browser->IsSame(browser)) return true;
  }
  // A native dialog must not run inside Chromium's navigation callback.
  CefPostTask(TID_UI, new PromptTask([prompt = owner_->config.external_app_prompt, requester, url] {
    prompt(requester, url);
  }));
  return true;
}

void DesktopCefClient::ReplayPopupAsTab(CefRefPtr<CefBrowser> opener, const std::string& url) {
  if (url.empty()) return;
  // A native pop-up is not a tab, so its pages open tabs in the partition of
  // the tab that opened it. A missing or closing source opens nothing rather
  // than falling back to the default store.
  const DesktopEngine::Impl::Tab* source = nullptr;
  for (const auto& tab : owner_->tabs) {
    const bool match = opener_ != 0 ? tab.browser->GetIdentifier() == opener_ : tab.browser->IsSame(opener);
    if (match) source = &tab;
  }
  if (source == nullptr || source->closing) return;
  NewTabRequest request;
  request.url = url;
  request.partition = source->partition;
  if (source->partition) {
    const auto* entry = owner_->partitions.Find(*source->partition);
    if (entry == nullptr || entry->deleting) return;
    request.persistent = entry->persistent;
  }
  TabSnapshot created;
  if (!owner_->CreateTabOnUi(request, &created).ok) return;
  auto* tab = owner_->FindTab(TabLease{created.id, created.generation});
  if (tab == nullptr) return;
#if defined(_WIN32)
  if (owner_->browser && owner_->browser->GetHost()) ShowWindow(owner_->browser->GetHost()->GetWindowHandle(), SW_HIDE);
  if (tab->browser && tab->browser->GetHost()) ShowWindow(tab->browser->GetHost()->GetWindowHandle(), SW_SHOW);
#endif
  owner_->browser = tab->browser;
  owner_->UpdateActiveState();
}

}  // namespace kelpie
