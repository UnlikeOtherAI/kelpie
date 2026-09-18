#pragma once

#include <chrono>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

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
};

struct BrowserControlResult {
  bool ok = false;
  std::string error_code;
  std::string message;
  std::optional<TabSnapshot> tab;
  // A timed-out browser command may already have caused a page side effect.
  bool operation_may_have_completed = false;

  static BrowserControlResult Success(std::optional<TabSnapshot> snapshot = std::nullopt) {
    return {true, {}, {}, std::move(snapshot), false};
  }

  static BrowserControlResult Failure(std::string code, std::string detail) {
    return {false, std::move(code), std::move(detail), std::nullopt, false};
  }
};

struct BrowserScreenshot {
  std::string mime_type = "image/png";
  std::string base64_data;
};

struct BrowserNavigationState {
  TabSnapshot tab;
  std::uint64_t requested = 0;
  std::uint64_t completed = 0;
  std::string error;
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
  virtual BrowserControlResult ResolveTab(const std::optional<std::string>& tab_id,
                                          const std::optional<std::uint64_t>& generation,
                                          TabLease* lease,
                                          Timeout timeout) = 0;
  virtual BrowserControlResult CreateTab(std::string url, TabSnapshot* tab, Timeout timeout) = 0;
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
};

}  // namespace kelpie
