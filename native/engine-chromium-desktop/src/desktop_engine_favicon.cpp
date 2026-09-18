#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "include/cef_image.h"
#include "kelpie/base64.h"
#include "kelpie/favicon_registry.h"

#include "desktop_cef_client.h"

// Favicon capture for the desktop engine.
//
// Chromium reports a page's icon URLs through CefDisplayHandler; fetching the
// bytes is a separate asynchronous download. Both halves live here so the rest
// of the client stays about navigation and lifecycle.
namespace kelpie {

FaviconRegistry& DesktopEngine::favicons() { return impl_->favicons; }

namespace {

// Receives the decoded icon on the UI thread and hands the PNG to the engine.
class FaviconDownloadCallback final : public CefDownloadImageCallback {
 public:
  FaviconDownloadCallback(std::weak_ptr<DesktopEngine::Impl> owner, CefRefPtr<CefBrowser> browser)
      : owner_(std::move(owner)), browser_(std::move(browser)) {}

  void OnDownloadImageFinished(const CefString&,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    const auto owner = owner_.lock();
    // The download outlives nothing: a tab can close, and the engine can shut
    // down, between the request and this callback. Both are checked here rather
    // than trusted.
    if (!owner || owner->shutting_down.load() || !image || image->IsEmpty()) {
      return;
    }
    if (http_status_code != 0 && http_status_code != 200) {
      return;
    }

    // CefImage holds every scale factor the site offered. Ask for 2x first,
    // which is the 32 px representation of a 16 px favicon, and fall back to 1x
    // (16 px) when the site ships only one size. Requesting the larger one first
    // keeps the tab pill crisp at 150 % and 200 % DPI.
    int width = 0;
    int height = 0;
    CefRefPtr<CefBinaryValue> png = image->GetAsPNG(2.0F, true, width, height);
    if (!png || png->GetSize() == 0) {
      png = image->GetAsPNG(1.0F, true, width, height);
    }
    if (!png || png->GetSize() == 0) {
      return;
    }

    std::vector<std::uint8_t> bytes(png->GetSize());
    const std::size_t copied = png->GetData(bytes.data(), bytes.size(), 0);
    if (copied != bytes.size()) {
      return;
    }
    owner->StoreFavicon(browser_, Base64Encode(bytes));
  }

 private:
  std::weak_ptr<DesktopEngine::Impl> owner_;
  CefRefPtr<CefBrowser> browser_;

  IMPLEMENT_REFCOUNTING(FaviconDownloadCallback);
};

}  // namespace

void DesktopEngine::Impl::StoreFavicon(CefRefPtr<CefBrowser> browser, std::string png_base64) {
  Tab* tab = FindTab(browser);
  if (tab == nullptr || png_base64.empty()) {
    return;
  }
  const std::string host = FaviconRegistry::HostForUrl(tab->url);
  auto shared = std::make_shared<const std::string>(std::move(png_base64));
  tab->favicon_png_base64 = shared;
  if (!host.empty()) {
    favicons.Store(host, *shared);
  }
}

void DesktopCefClient::OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                                          const std::vector<CefString>& icon_urls) {
  auto* tab = owner_->FindTab(browser);
  if (tab == nullptr || !browser || !browser->GetHost()) {
    return;
  }
  if (icon_urls.empty()) {
    // The page dropped its icon: clear the tab's so the strip falls back to the
    // letter avatar instead of showing the previous site's favicon.
    tab->favicon_url.clear();
    tab->favicon_png_base64.reset();
    return;
  }

  const std::string icon_url = icon_urls.front().ToString();
  if (icon_url.empty() || icon_url == tab->favicon_url) {
    return;
  }
  tab->favicon_url = icon_url;
  // `is_favicon` suppresses cookies on the request. `max_image_size` of 32
  // filters out anything larger in DIP terms, leaving the 16 px and 32 px
  // representations the tab strip needs.
  browser->GetHost()->DownloadImage(icon_url, /*is_favicon=*/true, /*max_image_size=*/32U,
                                    /*bypass_cache=*/false,
                                    new FaviconDownloadCallback(owner_->weak_from_this(), browser));
}

}  // namespace kelpie
