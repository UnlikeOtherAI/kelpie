#include "desktop_cef_client.h"

namespace kelpie {
namespace {
uint64_t DownloadId(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item) {
  return (static_cast<uint64_t>(browser->GetIdentifier()) << 32) | item->GetId();
}
}  // namespace

DesktopCefClient::BeforeDownloadResult DesktopCefClient::OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                                        const CefString& name, CefRefPtr<CefBeforeDownloadCallback> callback) {
  const auto path = owner_->config.downloads->Begin(DownloadId(browser, item), name.ToString(), owner_->config.download_directory);
  if (!path.empty()) callback->Continue(path.native(), false);
  return static_cast<BeforeDownloadResult>(true);
}

void DesktopCefClient::OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                                         CefRefPtr<CefDownloadItemCallback>) {
  if (item->IsValid() && !item->IsInProgress()) {
    owner_->config.downloads->Finish(DownloadId(browser, item), item->IsComplete());
  }
}
}  // namespace kelpie
