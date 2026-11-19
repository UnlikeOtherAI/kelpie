#include "network_handler.h"

namespace kelpie {

NetworkHandler::NetworkHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void NetworkHandler::Register(DesktopRouter& router) const {
  router.Register("get-network-log",
                  [this](const nlohmann::json& params) { return GetNetworkLog(params); });
  router.Register("clear-network-log", [this](const nlohmann::json& p) { if (const auto invalid = RejectBrowserWideTab(p)) return *invalid; return ClearNetworkLog(); });
  router.Register("network-clear", [this](const nlohmann::json& p) { if (const auto invalid = RejectBrowserWideTab(p)) return *invalid; return ClearNetworkLog(); });
  router.Register("get-resource-timeline",
                  [](const nlohmann::json&) { return Unsupported("get-resource-timeline"); }, false);
}

namespace {

std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char letter) {
    return static_cast<char>(std::tolower(letter));
  });
  return value;
}

nlohmann::json KnownString(std::string value) {
  return value.empty() ? nlohmann::json(nullptr) : nlohmann::json(std::move(value));
}

bool MatchesStatus(const std::string& filter, int status, bool failed) {
  if (filter == "error") return failed || status >= 400;
  if (filter == "success") return !failed && status >= 200 && status < 400;
  if (filter == "pending") return !failed && status == 0;
  return true;
}

}  // namespace

nlohmann::json NetworkHandler::GetNetworkLog(const nlohmann::json& params) const {
  std::optional<std::string> tab_id;
  if (const auto invalid = DiagnosticScope(runtime_, params, &tab_id)) return *invalid;
  if (runtime_.network_store == nullptr) return Unsupported("get-network-log");

  const auto type_arg = params.find("type");
  const auto status_arg = params.find("status");
  const std::string type_filter = type_arg != params.end() && type_arg->is_string() ? Lower(*type_arg) : "";
  const std::string category = status_arg != params.end() && status_arg->is_string() ? Lower(*status_arg) : "";
  const auto since = DiagnosticSince(params);
  const nlohmann::json entries = ParseJsonText(runtime_.network_store->ToJson());
  const auto limit = static_cast<std::size_t>(std::max(0, IntOrDefault(params, "limit", 200)));
  nlohmann::json filtered = nlohmann::json::array();
  std::int64_t transferred = 0;
  std::size_t total_requests = 0;
  std::size_t errors = 0;
  int load_time = 0;
  nlohmann::json by_type = nlohmann::json::object();
  for (const auto& entry : entries) {
    if (tab_id && entry.value("tabId", "") != *tab_id) continue;
    const std::string type = Lower(entry.value("resource_type", entry.value("category", "Other")));
    if (!type_filter.empty() && type != type_filter) continue;
    const std::string started = entry.value("start_time", "");
    if (since && ParseDiagnosticTimestamp(started).value_or(0) < *since) continue;
    const int status = entry.value("status_code", 0);
    const std::string failure = entry.value("failure", "");
    const auto encoded = entry.value("size", std::int64_t{0});
    const int duration = entry.value("duration", 0);

    ++total_requests;
    by_type[type] = by_type.value(type, 0) + 1;
    if (MatchesStatus("error", status, !failure.empty())) ++errors;
    transferred += encoded;
    load_time = std::max(load_time, duration);
    if (!MatchesStatus(category, status, !failure.empty())) continue;

    nlohmann::json item = {
        {"url", entry.value("url", "")},
        {"type", type},
        {"method", KnownString(entry.value("request_method", entry.value("method", "")))},
        {"status", status > 0 ? nlohmann::json(status) : nlohmann::json(nullptr)},
        {"statusText", KnownString(entry.value("status_text", ""))},
        {"mimeType", KnownString(entry.value("content_type", ""))},
        {"size", nullptr},
        {"transferSize", encoded > 0 ? nlohmann::json(encoded) : nlohmann::json(nullptr)},
        {"timing", {{"started", started}, {"total", duration}}},
        {"initiator", entry.value("initiator", "browser")},
    };
    if (entry.contains("tabId")) item["tabId"] = entry["tabId"];
    if (!failure.empty()) item["failure"] = failure;
    filtered.push_back(std::move(item));
  }

  const bool has_more = filtered.size() > limit;
  if (has_more) filtered.erase(filtered.begin(), filtered.begin() + (filtered.size() - limit));

  return SuccessResponse({
      {"entries", filtered},
      {"count", filtered.size()},
      {"hasMore", has_more},
      {"summary", {
          {"totalRequests", total_requests}, {"totalSize", 0}, {"totalTransferSize", transferred},
          {"byType", by_type}, {"errors", errors}, {"loadTime", load_time},
      }},
  });
}

nlohmann::json NetworkHandler::ClearNetworkLog() const {
  if (runtime_.network_store == nullptr) {
    return Unsupported("clear-network-log");
  }
  const int count = runtime_.network_store->Count();
  runtime_.network_store->Clear();
  return SuccessResponse({{"cleared", count}});
}

}  // namespace kelpie
