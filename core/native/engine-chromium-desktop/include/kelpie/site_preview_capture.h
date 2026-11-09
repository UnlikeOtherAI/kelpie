#pragma once

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>

#include "kelpie/desktop_browser_control.h"
#include "kelpie/site_preview_store.h"

namespace kelpie {

// Keeps the start page's site screenshots current.
//
// The engine reports every navigation, title and load event; this worker waits
// for those to settle, then captures the active tab once through the fixed
// `CaptureSitePreview` observation, scales it down and stores it with the tab's
// favicon. Capturing runs on its own thread because the DevTools round trip
// waits on the CEF UI thread, which must keep pumping meanwhile.
//
// Only the active tab is captured, so the picture is of what the person is
// looking at, and only ordinary web pages in persistent storage: start pages,
// errors, in-memory partitions and pages still loading are skipped. When
// history is cleared, screenshots of sites that are not favourites go with it.
class SitePreviewCapture {
 public:
  // Base64 viewport capture in, stored preview JPEG out; nullopt to discard.
  using Encoder = std::function<std::optional<std::string>(const std::string& capture_base64)>;
  // Hosts whose previews survive a history clear: the current favourites.
  using HostsSupplier = std::function<std::unordered_set<std::string>()>;
  using GenerationSupplier = std::function<std::uint64_t()>;

  struct Options {
    // Quiet time after the last navigation event before capturing, so the page
    // has painted its first screen.
    std::chrono::milliseconds settle{1500};
    // A host is captured at most this often while browsing around it.
    std::chrono::milliseconds refresh{std::chrono::minutes(2)};
    // How often the worker checks whether history was cleared.
    std::chrono::milliseconds poll{std::chrono::seconds(5)};
    DesktopBrowserControl::Timeout capture_timeout{std::chrono::seconds(4)};
  };

  SitePreviewCapture(DesktopBrowserControl& browser, SitePreviewStore& store, Encoder encoder,
                     HostsSupplier retained_hosts, GenerationSupplier history_generation,
                     Options options);
  SitePreviewCapture(DesktopBrowserControl& browser, SitePreviewStore& store, Encoder encoder,
                     HostsSupplier retained_hosts, GenerationSupplier history_generation)
      : SitePreviewCapture(browser, store, std::move(encoder), std::move(retained_hosts),
                           std::move(history_generation), Options()) {}
  ~SitePreviewCapture();

  SitePreviewCapture(const SitePreviewCapture&) = delete;
  SitePreviewCapture& operator=(const SitePreviewCapture&) = delete;

  void Start();
  // Any navigation, title or load change. Restarts the settle timer.
  void NotifyNavigation();
  // Nonblocking: asks the worker to finish. An in-flight capture is bounded by
  // `capture_timeout`, and the owner keeps pumping CEF until IsStopped().
  void BeginStop();
  bool IsStopped() const;
  // Joins the finished worker. Call only once IsStopped() is true.
  void Join();

 private:
  void Run();
  void CaptureActiveTab();
  void PruneIfHistoryCleared();

  DesktopBrowserControl& browser_;
  SitePreviewStore& store_;
  Encoder encoder_;
  HostsSupplier retained_hosts_;
  GenerationSupplier history_generation_;
  Options options_;

  std::mutex mutex_;
  std::condition_variable wake_;
  std::optional<std::chrono::steady_clock::time_point> deadline_;
  bool stopping_ = false;
  std::atomic<bool> stopped_{true};
  std::thread worker_;

  // Worker-thread state.
  std::uint64_t seen_generation_ = 0;
  std::unordered_map<std::string, std::chrono::steady_clock::time_point> captured_at_;
};

}  // namespace kelpie
