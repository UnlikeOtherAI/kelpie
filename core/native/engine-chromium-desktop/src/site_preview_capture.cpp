#include "kelpie/site_preview_capture.h"

#include <algorithm>
#include <cctype>
#include <utility>
#include <vector>

#include "kelpie/favicon_registry.h"
#include "site_preview_image.h"

namespace kelpie {
namespace {

bool IsWebUrl(const std::string& url) {
  std::string scheme = url.substr(0, std::min<std::size_t>(url.size(), 8));
  std::transform(scheme.begin(), scheme.end(), scheme.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return scheme.rfind("http://", 0) == 0 || scheme.rfind("https://", 0) == 0;
}

}  // namespace

SitePreviewCapture::SitePreviewCapture(DesktopBrowserControl& browser, SitePreviewStore& store,
                                       Encoder encoder, HostsSupplier retained_hosts,
                                       GenerationSupplier history_generation, Options options)
    : browser_(browser),
      store_(store),
      encoder_(std::move(encoder)),
      retained_hosts_(std::move(retained_hosts)),
      history_generation_(std::move(history_generation)),
      options_(options) {}

SitePreviewCapture::~SitePreviewCapture() {
  BeginStop();
  if (worker_.joinable()) worker_.join();
}

void SitePreviewCapture::Start() {
  if (worker_.joinable()) return;
  seen_generation_ = history_generation_ ? history_generation_() : 0;
  stopped_ = false;
  worker_ = std::thread([this] { Run(); });
}

void SitePreviewCapture::NotifyNavigation() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    deadline_ = std::chrono::steady_clock::now() + options_.settle;
  }
  wake_.notify_one();
}

void SitePreviewCapture::BeginStop() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
  }
  wake_.notify_one();
}

bool SitePreviewCapture::IsStopped() const { return stopped_.load(); }

void SitePreviewCapture::Join() {
  if (worker_.joinable()) worker_.join();
}

void SitePreviewCapture::Run() {
  std::unique_lock<std::mutex> lock(mutex_);
  while (!stopping_) {
    const auto now = std::chrono::steady_clock::now();
    auto wake_at = now + options_.poll;
    if (deadline_ && *deadline_ < wake_at) wake_at = *deadline_;
    wake_.wait_until(lock, wake_at);
    if (stopping_) break;
    const bool due = deadline_ && std::chrono::steady_clock::now() >= *deadline_;
    if (due) deadline_.reset();
    lock.unlock();
    PruneIfHistoryCleared();
    if (due) CaptureActiveTab();
    lock.lock();
  }
  stopped_ = true;
}

void SitePreviewCapture::PruneIfHistoryCleared() {
  if (!history_generation_) return;
  const std::uint64_t generation = history_generation_();
  if (generation == seen_generation_) return;
  seen_generation_ = generation;
  captured_at_.clear();
  store_.RetainOnly(retained_hosts_ ? retained_hosts_() : std::unordered_set<std::string>{});
}

void SitePreviewCapture::CaptureActiveTab() {
  std::vector<TabSnapshot> tabs;
  if (!browser_.GetTabs(&tabs, std::chrono::seconds(1)).ok) return;
  const auto active = std::find_if(tabs.begin(), tabs.end(), [](const TabSnapshot& tab) { return tab.active; });
  // A tab still loading reports again when it finishes.
  if (active == tabs.end() || active->is_loading || active->is_start_page || !IsWebUrl(active->url)) return;
  if (active->partition && active->persistent == std::optional<bool>(false)) return;
  const std::string host = FaviconRegistry::HostForUrl(active->url);
  if (host.empty()) return;

  // The favicon often arrives after the first capture of a host; keep the
  // latest one whether or not a new screenshot is due.
  if (active->favicon_png_base64 && !active->favicon_png_base64->empty()) {
    if (const auto png = site_preview::DecodeBase64(*active->favicon_png_base64)) {
      std::string bytes(png->begin(), png->end());
      if (store_.Favicon(host) != bytes) store_.StoreFavicon(host, std::move(bytes));
    }
  }

  const auto now = std::chrono::steady_clock::now();
  const auto previous = captured_at_.find(host);
  if (previous != captured_at_.end() && now - previous->second < options_.refresh &&
      store_.ThumbnailVersion(host)) {
    return;
  }

  nlohmann::json captured;
  const TabLease lease{active->id, active->generation};
  if (!browser_.CaptureSitePreview(lease, &captured, options_.capture_timeout).ok) return;
  if (!captured.is_object() || !captured.contains("data") || !captured["data"].is_string()) return;
  // The capture is fenced to one document; it must still be the same site.
  if (FaviconRegistry::HostForUrl(captured.value("url", std::string())) != host) return;
  const auto preview = encoder_ ? encoder_(captured["data"].get<std::string>()) : std::nullopt;
  if (!preview || !store_.StoreThumbnail(host, *preview)) return;
  captured_at_[host] = now;
}

}  // namespace kelpie
