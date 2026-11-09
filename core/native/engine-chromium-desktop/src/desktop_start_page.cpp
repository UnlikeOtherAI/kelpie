#include "desktop_start_page.h"

#include <cstdint>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

#include "kelpie/base64.h"
#include "kelpie/favicon_registry.h"
#include "site_preview_codec.h"

namespace kelpie {

DesktopStartPage::DesktopStartPage(DesktopEngine& engine, HistoryStore& history,
                                   std::function<std::string()> bookmarks_json)
    : engine_(engine), history_(history), bookmarks_json_(std::move(bookmarks_json)) {}

DesktopStartPage::~DesktopStartPage() {
  if (capture_) {
    capture_->BeginStop();
    capture_->Join();
  }
}

void DesktopStartPage::Configure(const std::filesystem::path& previews_path,
                                 DesktopEngine::Config& engine_config) {
  previews_ = std::make_unique<SitePreviewStore>(previews_path);
  // Both suppliers run on the CEF IO thread; every store and the favicon
  // registry is mutex-guarded.
  engine_config.start_page_data_supplier = [this]() {
    return start_page::BuildDataJson(bookmarks_json_(), history_.ToJson(), start_page::kRecentSiteLimit,
                                     [this](const std::string& host) { return SiteImagesFor(host); });
  };
  engine_config.start_page_preview_supplier = [this](const std::string& host) {
    return previews_->Thumbnail(host);
  };
}

void DesktopStartPage::StartCapture() {
  if (!previews_ || capture_) return;
  capture_ = std::make_unique<SitePreviewCapture>(
      engine_, *previews_, site_preview::EncodePreview, [this] { return FavouriteHosts(); },
      [this] { return history_.ClearGeneration(); });
  capture_->Start();
}

void DesktopStartPage::NotifyNavigation() {
  if (capture_) capture_->NotifyNavigation();
}

void DesktopStartPage::BeginStop() {
  if (capture_) capture_->BeginStop();
}

bool DesktopStartPage::IsStopped() const { return !capture_ || capture_->IsStopped(); }

void DesktopStartPage::Stop() {
  if (!capture_) return;
  capture_->Join();
  capture_.reset();
}

std::unordered_set<std::string> DesktopStartPage::FavouriteHosts() const {
  std::unordered_set<std::string> hosts;
  const auto parsed = nlohmann::json::parse(bookmarks_json_(), nullptr, false);
  if (!parsed.is_array()) return hosts;
  for (const auto& node : parsed) {
    if (!node.is_object() || !node.contains("url") || !node["url"].is_string()) continue;
    const std::string host = FaviconRegistry::HostForUrl(node["url"].get<std::string>());
    if (!host.empty()) hosts.insert(host);
  }
  return hosts;
}

// The session's favicon first; the one stored with the site's screenshot
// otherwise, which is all a fresh launch has.
start_page::SiteImages DesktopStartPage::SiteImagesFor(const std::string& host) {
  start_page::SiteImages images;
  images.favicon_png_base64 = engine_.favicons().Peek(host).value_or(std::string());
  if (images.favicon_png_base64.empty()) {
    if (const auto png = previews_->Favicon(host)) {
      images.favicon_png_base64 = Base64Encode(std::vector<std::uint8_t>(png->begin(), png->end()));
    }
  }
  images.preview_version = previews_->ThumbnailVersion(host);
  return images;
}

}  // namespace kelpie
