#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

#include "kelpie/navigation_tracker.h"

namespace kelpie {

struct TabLease {
  std::string id;
  std::uint64_t generation = 0;
};

struct TabSnapshot {
  std::string id;
  std::uint64_t generation = 0;
  std::string url;
  std::string title;
  bool active = false;
  bool is_loading = false;
  bool can_go_back = false;
  bool can_go_forward = false;
  // Kelpie's own start page (`kelpie://start`). The macOS tab pill shows a star
  // instead of a favicon or letter avatar for it; the Windows tab strip mirrors
  // that. Mirrors `Tab.isStartPage` in the macOS app.
  bool is_start_page = false;
  // The page's favicon as a base64-encoded PNG, or null when none has been
  // downloaded yet.
  //
  // Base64 rather than raw bytes because every consumer — the `data:` URIs the
  // start page renders, and any future JSON transport — needs the encoded form,
  // so encoding once at the CEF boundary avoids repeating it per read.
  //
  // `shared_ptr<const std::string>` rather than `std::string` keeps TabSnapshot
  // cheap to copy: snapshots are taken on the browser owner thread for every
  // command result and every `get-tabs` entry, and a favicon is a few kilobytes.
  // The payload is immutable once captured, so sharing it is safe; a new favicon
  // replaces the pointer rather than mutating the string.
  std::shared_ptr<const std::string> favicon_png_base64;
  // Free-form caller label, shown in place of the page title in the tab strip.
  std::optional<std::string> name;
  // Storage container the tab is bound to. Absent means the default shared
  // store, which is what an ordinary Chrome tab uses.
  std::optional<std::string> partition;
  // Reported alongside `partition` so a caller learns what it actually got:
  // the first tab to resolve a partition fixes its persistence for the rest.
  std::optional<bool> persistent;
};

// Everything `new-tab` can ask for. `persistent` only means anything with a
// `partition`; the first tab to resolve a partition fixes it for the rest.
struct NewTabRequest {
  std::string url;
  std::optional<std::string> name;
  std::optional<std::string> partition;
  bool persistent = true;
};

struct PartitionInfo {
  std::string id;
  // Rebuilt from the live tab list on every read, never trusted from state.
  std::size_t tab_count = 0;
  bool persistent = true;
};

struct PartitionDeletion {
  bool existed = false;
  std::size_t tabs_closed = 0;
};

struct BrowserControlResult {
  bool ok = false;
  std::string error_code;
  std::string message;
  std::optional<TabSnapshot> tab;
  // A timed-out browser command may already have caused a page side effect.
  bool operation_may_have_completed = false;
  // Extra machine-actionable fields merged into the HTTP error body, such as
  // the `reason` discriminator PARTITION_UNSUPPORTED carries.
  nlohmann::json details = nlohmann::json::object();

  static BrowserControlResult Success(std::optional<TabSnapshot> snapshot = std::nullopt) {
    return {true, {}, {}, std::move(snapshot), false, nlohmann::json::object()};
  }

  static BrowserControlResult Failure(std::string code, std::string detail) {
    return {false, std::move(code), std::move(detail), std::nullopt, false,
            nlohmann::json::object()};
  }

  static BrowserControlResult Failure(std::string code, std::string detail,
                                      nlohmann::json extra) {
    return {false, std::move(code), std::move(detail), std::nullopt, false, std::move(extra)};
  }
};

// What `screenshot` may ask of the engine. The handler validates the request;
// the engine trusts these values.
struct BrowserScreenshotOptions {
  std::string format = "png";  // "png" or "jpeg"
  // JPEG compression, 1-100. Ignored for PNG, as on iOS, Android and macOS.
  std::optional<int> quality;
  // Largest image width in pixels. The image is scaled down to fit, never up.
  std::optional<int> max_width;
};

struct BrowserScreenshot {
  std::string mime_type = "image/png";
  std::string base64_data;
  // The encoded image's own pixel size, read from its header rather than from
  // the request, so a scale the engine got wrong shows up instead of hiding.
  int width = 0;
  int height = 0;
  // The CSS viewport the image shows, and the device pixels per CSS pixel, so
  // a caller can map image pixels back to page coordinates.
  double viewport_width = 0;
  double viewport_height = 0;
  double device_pixel_ratio = 1;
};

struct BrowserNavigationState {
  TabSnapshot tab;
  NavigationTracker navigation;
};

// The shared router uses this interface instead of accessing a CEF renderer
// directly. Implementations serialize operations on the browser owner thread
// and validate the lease for the full operation.
class DesktopBrowserControl {
 public:
  using Json = nlohmann::json;
  using Timeout = std::chrono::milliseconds;

  virtual ~DesktopBrowserControl() = default;

  virtual BrowserControlResult GetTabs(std::vector<TabSnapshot>* tabs, Timeout timeout) = 0;
  virtual BrowserControlResult GetNavigationState(TabLease,
                                                  BrowserNavigationState*,
                                                  Timeout) {
    return BrowserControlResult::Failure("UNSUPPORTED", "Navigation state is unavailable");
  }
  // Called before a navigation-capable action (click, fill, evaluate, ...)
  // runs, so a later `wait-for-navigation` waits for what that action starts
  // rather than an earlier navigation. An engine without navigation tracking
  // has no baseline to move.
  virtual BrowserControlResult MarkNavigationAction(TabLease, Timeout) {
    return BrowserControlResult::Success();
  }
  virtual BrowserControlResult ResolveTab(const std::optional<std::string>& tab_id,
                                          const std::optional<std::uint64_t>& generation,
                                          TabLease* lease,
                                          Timeout timeout) = 0;
  virtual BrowserControlResult CreateTab(const NewTabRequest& request,
                                        TabSnapshot* tab,
                                        Timeout timeout) = 0;
  // Convenience for the many call sites that only want a URL in the default
  // shared store. Deliberately non-virtual so there is one implementation.
  BrowserControlResult CreateTab(std::string url, TabSnapshot* tab, Timeout timeout) {
    NewTabRequest request;
    request.url = std::move(url);
    return CreateTab(request, tab, timeout);
  }
  // Partition support is engine-specific. An engine that cannot isolate
  // storage says so here rather than letting a caller believe it did.
  virtual BrowserControlResult GetPartitions(std::vector<PartitionInfo>*, Timeout) {
    return PartitionsUnsupported();
  }
  virtual BrowserControlResult DeletePartition(const std::string&, PartitionDeletion*, Timeout) {
    return PartitionsUnsupported();
  }
  virtual BrowserControlResult ActivateTab(TabLease lease, Timeout timeout) = 0;
  virtual BrowserControlResult CloseTab(TabLease lease, Timeout timeout) = 0;
  virtual BrowserControlResult Navigate(std::optional<TabLease> lease,
                                        std::string url,
                                        TabSnapshot* tab,
                                        Timeout timeout) = 0;
  virtual BrowserControlResult Back(TabLease lease, TabSnapshot* tab, Timeout timeout) = 0;
  virtual BrowserControlResult Forward(TabLease lease, TabSnapshot* tab, Timeout timeout) = 0;
  virtual BrowserControlResult Reload(TabLease lease, TabSnapshot* tab, Timeout timeout) = 0;
  virtual BrowserControlResult Evaluate(TabLease lease,
                                        std::string script,
                                        Json* value,
                                        Timeout timeout) = 0;
  virtual BrowserControlResult Screenshot(TabLease lease,
                                          const BrowserScreenshotOptions& options,
                                          BrowserScreenshot* image,
                                          Timeout timeout) = 0;
  virtual BrowserControlResult GetCookies(TabLease lease,
                                          const Json& query,
                                          Json* cookies,
                                          Timeout timeout) = 0;
  virtual BrowserControlResult SetCookies(TabLease lease,
                                          const Json& cookies,
                                          Json* result,
                                          Timeout timeout) = 0;
  virtual BrowserControlResult DeleteCookies(TabLease lease,
                                             const Json& query,
                                             Json* result,
                                             Timeout timeout) = 0;
  virtual BrowserControlResult DispatchTrustedInput(TabLease lease,
                                                    const Json& input,
                                                    Json* result,
                                                    Timeout timeout) = 0;
  virtual BrowserControlResult GetDialog(TabLease lease, Json* dialog, Timeout timeout) = 0;
  virtual BrowserControlResult HandleDialog(TabLease lease,
                                            const Json& action,
                                            Json* result,
                                            Timeout timeout) = 0;
  // Provides trusted CEF DevTools methods such as Input.dispatchKeyEvent,
  // Input.dispatchMouseEvent, Page.handleJavaScriptDialog, and DOM queries.
  virtual BrowserControlResult DevTools(TabLease lease,
                                        std::string method,
                                        const Json& params,
                                        Json* result,
                                        Timeout timeout) = 0;

 protected:
  static BrowserControlResult PartitionsUnsupported() {
    // `activeEngine` is omitted rather than nulled when there is no engine to
    // name, matching the macOS envelope.
    return BrowserControlResult::Failure(
        "PARTITION_UNSUPPORTED", "This build has no browser engine that can isolate storage",
        {{"reason", "platform-single-tab"},
         {"hint", "use a Kelpie build with the Chromium desktop engine"}});
  }
};

}  // namespace kelpie
