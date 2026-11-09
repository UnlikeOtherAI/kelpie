// Store-level cookie access for automation (get-cookies all/partition,
// set-cookies, copy-cookies) and the default-store load signal for cookie
// sync. Stores are CefCookieManagers, never a tab's DevTools session: the
// global manager for the default store, a partition's CefRequestContext
// manager otherwise. No tab lease is held across the cookie calls.
#include <chrono>
#include <memory>
#include <utility>

#include "desktop_cookie_store.h"
#include "desktop_cookie_store_cef.h"
#include "desktop_engine_impl.h"
#include "kelpie/partition.h"

namespace kelpie {
namespace {

using Json = nlohmann::json;

struct ResolvedStore {
  CefRefPtr<CefCookieManager> manager;
  std::string identity;  // "default" or "partition:<id>"
};

desktop_cookie_store::Cancelled Deadline(DesktopBrowserControl::Timeout timeout) {
  const auto until = std::chrono::steady_clock::now() + timeout;
  return [until] { return std::chrono::steady_clock::now() >= until; };
}

BrowserControlResult Resolve(DesktopEngine& engine, const std::shared_ptr<DesktopEngine::Impl>& impl,
                             const CookieStoreTarget& target, ResolvedStore* store,
                             DesktopBrowserControl::Timeout timeout) {
  if (target.tab_id && target.partition) {
    return BrowserControlResult::Failure("INVALID_PARAMS", "Use tabId or partition, not both");
  }
  if (target.partition) {
    const PartitionValidation validation = ValidatePartition(*target.partition);
    if (!validation.ok) {
      return BrowserControlResult::Failure("INVALID_PARTITION", "Invalid partition \"" + *target.partition +
                                                                    "\": " + PartitionErrorMessage(validation.reason));
    }
  }
  std::optional<TabLease> lease;
  if (target.tab_id) {
    TabLease resolved;
    const auto result = engine.ResolveTab(target.tab_id, target.generation, &resolved, timeout);
    if (!result.ok) return result;
    lease = resolved;
  }
  auto captured = std::make_shared<ResolvedStore>();
  const auto result = impl->RunOnUi([impl, lease, partition = target.partition, captured] {
    std::optional<std::string> store_partition = partition;
    if (lease) {
      auto* tab = impl->FindTab(*lease);
      if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
      store_partition = tab->partition;
    }
    if (store_partition) {
      auto* entry = impl->partitions.Find(*store_partition);
      if (!entry || entry->deleting || !entry->ready() || !entry->context) {
        return BrowserControlResult::Failure("PARTITION_NOT_FOUND",
                                             "No open tab uses partition \"" + *store_partition + "\"");
      }
      captured->manager = entry->context->GetCookieManager(nullptr);
      captured->identity = "partition:" + *store_partition;
    } else {
      captured->manager = CefCookieManager::GetGlobalManager(nullptr);
      captured->identity = "default";
    }
    if (!captured->manager) return BrowserControlResult::Failure("WEBVIEW_ERROR", "The cookie store is unavailable");
    return BrowserControlResult::Success();
  }, timeout);
  if (result.ok) *store = *captured;
  return result;
}

BrowserControlResult StoreUnavailable() {
  BrowserControlResult result = BrowserControlResult::Failure("WEBVIEW_ERROR", "The cookie store could not be read");
  return result;
}

}  // namespace

void DesktopEngine::Impl::NotifyDefaultStoreLoad() {
  std::function<void()> sink;
  {
    std::lock_guard lock(default_store_sink_mutex);
    sink = default_store_sink;
  }
  if (sink) sink();
}

void DesktopEngine::SetDefaultStoreLoadSink(std::function<void()> sink) {
  std::lock_guard lock(impl_->default_store_sink_mutex);
  impl_->default_store_sink = std::move(sink);
}

BrowserControlResult DesktopEngine::ReadCookieStore(const CookieStoreTarget& target, Json* cookies, Timeout timeout) {
  if (!cookies) return BrowserControlResult::Failure("INTERNAL", "cookies is required");
  const auto cancelled = Deadline(timeout);
  ResolvedStore store;
  const auto resolved = Resolve(*this, impl_, target, &store, timeout);
  if (!resolved.ok) return resolved;
  CefCookieBackend backend(store.manager);
  Json wire;
  if (!backend.VisitAll(&wire, cancelled)) return StoreUnavailable();
  Json out = Json::array();
  for (const auto& cookie : wire) out.push_back(desktop_cookie_store::ToAutomation(cookie));
  *cookies = std::move(out);
  return BrowserControlResult::Success();
}

BrowserControlResult DesktopEngine::WriteCookieStore(const CookieStoreTarget& target, const Json& cookies,
                                                     Json* result, Timeout timeout) {
  if (!result) return BrowserControlResult::Failure("INTERNAL", "result is required");
  const auto cancelled = Deadline(timeout);
  ResolvedStore store;
  const auto resolved = Resolve(*this, impl_, target, &store, timeout);
  if (!resolved.ok) return resolved;
  if (!cookies.is_array()) return BrowserControlResult::Failure("INVALID_PARAMS", "cookies must be an array");
  CefCookieBackend backend(store.manager);
  *result = desktop_cookie_store::WriteCookies(backend, std::vector<Json>(cookies.begin(), cookies.end()), cancelled);
  return BrowserControlResult::Success();
}

BrowserControlResult DesktopEngine::CopyCookieStore(const CookieStoreTarget& from, const CookieStoreTarget& to,
                                                    const std::optional<std::string>& domain, Json* result,
                                                    Timeout timeout) {
  if (!result) return BrowserControlResult::Failure("INTERNAL", "result is required");
  const auto cancelled = Deadline(timeout);
  ResolvedStore source, target;
  auto resolved = Resolve(*this, impl_, from, &source, timeout);
  if (!resolved.ok) return resolved;
  resolved = Resolve(*this, impl_, to, &target, timeout);
  if (!resolved.ok) return resolved;
  if (source.identity == target.identity) {
    return BrowserControlResult::Failure("INVALID_PARAMS", "from and to name the same cookie store");
  }
  CefCookieBackend reader(source.manager), writer(target.manager);
  const auto copied = desktop_cookie_store::CopyCookies(reader, writer, domain, cancelled);
  if (!copied) return StoreUnavailable();
  *result = *copied;
  return BrowserControlResult::Success();
}

}  // namespace kelpie
