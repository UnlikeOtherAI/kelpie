// Store-level cookie methods: get-cookies with all/partition, set-cookies,
// copy-cookies and get-cookie-sync-status. They address a whole cookie store
// (the default store, a partition or a tab's store), not the current page.
#include "cookie_handler.h"

#include <algorithm>
#include <vector>

#include "desktop_cookie_store.h"

namespace kelpie {
namespace {

std::optional<std::string> OptionalText(const nlohmann::json& params, const char* key) {
  const auto it = params.find(key);
  if (it == params.end() || it->is_null()) return std::nullopt;
  if (!it->is_string() || it->get<std::string>().empty()) {
    throw std::invalid_argument(std::string(key) + " must be a non-empty string");
  }
  return it->get<std::string>();
}

// {tabId?, generation?, partition?} → a store; neither tab nor partition is the default store.
CookieStoreTarget StoreTarget(const nlohmann::json& params) {
  if (!params.is_object()) throw std::invalid_argument("a cookie store must be an object");
  CookieStoreTarget target;
  target.tab_id = OptionalTabId(params);
  target.generation = OptionalGeneration(params);
  target.partition = OptionalText(params, "partition");
  if (target.tab_id && target.partition) throw std::invalid_argument("Use tabId or partition, not both");
  if (target.generation && !target.tab_id) throw std::invalid_argument("generation requires tabId");
  return target;
}

bool SameTarget(const CookieStoreTarget& a, const CookieStoreTarget& b) {
  return a.tab_id == b.tab_id && a.partition == b.partition;
}

}  // namespace

nlohmann::json CookieHandler::GetStoreCookies(const nlohmann::json& params) const {
  const CookieStoreTarget target = StoreTarget(params);
  const auto domain = OptionalText(params, "domain");
  const auto name = OptionalText(params, "name");
  const auto url = OptionalText(params, "url");
  if (url && !desktop_cookie_store::MatchesUrl(nlohmann::json::object(), *url)) {
    return InvalidParams("url must be an absolute http(s) URL");
  }
  nlohmann::json cookies;
  const auto result = RequireBrowserControl(runtime_).ReadCookieStore(target, &cookies, ControlTimeout(params));
  if (!result.ok) return ControlError(result);
  nlohmann::json filtered = desktop_cookie_store::Filter(cookies, domain, name, url);
  nlohmann::json body = {{"count", filtered.size()}, {"cookies", std::move(filtered)}};
  // The whole store was enumerated, so an all:true listing is complete.
  if (params.value("all", false) == true) body["complete"] = true;
  return SuccessResponse(body);
}

nlohmann::json CookieHandler::SetCookies(const nlohmann::json& params) const {
  try {
    const auto cookies = params.find("cookies");
    if (cookies == params.end() || !cookies->is_array() || cookies->empty() ||
        cookies->size() > desktop_cookie_store::kMaxCookiesPerWrite) {
      return InvalidParams("cookies must be an array of 1 to 500 cookies");
    }
    const CookieStoreTarget target = StoreTarget(params);
    // A malformed cookie fails only itself (INVALID_COOKIE), as on every platform;
    // the rest are still written.
    nlohmann::json valid = nlohmann::json::array();
    std::vector<std::size_t> original_index;
    nlohmann::json failed = nlohmann::json::array();
    for (std::size_t i = 0; i < cookies->size(); ++i) {
      std::string error;
      const auto one = desktop_cookie_store::ParseCookies(nlohmann::json::array({(*cookies)[i]}), &error);
      if (!one) {
        const auto& item = (*cookies)[i];
        const auto text = [&](const char* field) {
          return item.is_object() && item.contains(field) && item[field].is_string() ? item[field] : nlohmann::json();
        };
        failed.push_back({{"index", i}, {"name", text("name")}, {"domain", text("domain")}, {"error", "INVALID_COOKIE"}});
        continue;
      }
      valid.push_back((*one)[0]);
      original_index.push_back(i);
    }
    nlohmann::json output = {{"set", 0}, {"failed", nlohmann::json::array()}};
    if (!valid.empty()) {
      const auto result = RequireBrowserControl(runtime_).WriteCookieStore(target, valid, &output, ControlTimeout(params));
      if (!result.ok) return ControlError(result);
    }
    for (auto refused : output.value("failed", nlohmann::json::array())) {
      const auto at = refused.value("index", std::size_t{0});
      refused["index"] = at < original_index.size() ? original_index[at] : at;
      failed.push_back(std::move(refused));
    }
    std::sort(failed.begin(), failed.end(), [](const nlohmann::json& a, const nlohmann::json& b) {
      return a.value("index", std::size_t{0}) < b.value("index", std::size_t{0});
    });
    output["failed"] = std::move(failed);
    return SuccessResponse(output);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json CookieHandler::CopyCookies(const nlohmann::json& params) const {
  try {
    const auto from = params.find("from");
    const auto to = params.find("to");
    if (from == params.end() || to == params.end()) return InvalidParams("copy-cookies requires from and to");
    const CookieStoreTarget source = StoreTarget(*from);
    const CookieStoreTarget destination = StoreTarget(*to);
    if (SameTarget(source, destination)) {
      return InvalidParams("from and to name the same cookie store");
    }
    const auto domain = OptionalText(params, "domain");
    nlohmann::json output;
    const auto result =
        RequireBrowserControl(runtime_).CopyCookieStore(source, destination, domain, &output, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return SuccessResponse(output);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json CookieHandler::GetCookieSyncStatus(const nlohmann::json&) const {
  if (runtime_.cookie_sync_status) return SuccessResponse(runtime_.cookie_sync_status());
  // No sync service in this shell: a desktop build without the Chromium engine.
  return SuccessResponse({{"supported", false}, {"reason", "no-cef"}, {"signedIn", false}, {"listening", false},
                          {"peers", nlohmann::json::array()},
                          {"store", {{"entries", 0}, {"tombstones", 0}, {"localOnly", 0}, {"unapplied", 0},
                                     {"skipped", 0}, {"warming", false}, {"lastPurgeAt", nullptr}}}});
}

}  // namespace kelpie
