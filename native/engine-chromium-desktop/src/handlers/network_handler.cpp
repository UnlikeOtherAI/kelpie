#include "network_handler.h"

namespace kelpie {

NetworkHandler::NetworkHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void NetworkHandler::Register(DesktopRouter& router) const {
  router.Register("get-network-log",
                  [this](const nlohmann::json& params) { return GetNetworkLog(params); });
  router.Register("clear-network-log",
                  [this](const nlohmann::json&) { return ClearNetworkLog(); });
  router.Register("network-clear", [this](const nlohmann::json&) { return ClearNetworkLog(); });
  router.Register("get-resource-timeline",
                  [](const nlohmann::json&) { return Unsupported("get-resource-timeline"); });
}

nlohmann::json NetworkHandler::GetNetworkLog(const nlohmann::json& params) const {
  if (runtime_.network_store == nullptr) {
    return SuccessResponse({
        {"entries", nlohmann::json::array()},
        {"count", 0},
        {"hasMore", false},
        {"summary", nlohmann::json::object()},
    });
  }

  const auto type_it = params.find("type");
  const auto status_it = params.find("status");
  nlohmann::json entries = ParseJsonText(runtime_.network_store->ToJson());
  const int limit = std::max(1, IntOrDefault(params, "limit", 200));
  nlohmann::json filtered = nlohmann::json::array();

  for (const auto& entry : entries) {
    if (type_it != params.end() && type_it->is_string() &&
        entry.value("category", "") != type_it->get<std::string>()) {
      continue;
    }
    if (status_it != params.end() && status_it->is_string()) {
      const int status_code = entry.value("status_code", 0);
      const std::string filter = status_it->get<std::string>();
      if ((filter == "success" && status_code >= 400) ||
          (filter == "error" && status_code < 400) ||
          (filter == "pending" && status_code != 0)) {
        continue;
      }
    }
    filtered.push_back({
        {"url", entry.value("url", "")},
        {"type", entry.value("category", "Other")},
        {"method", entry.value("method", "GET")},
        {"status", entry.value("status_code", 0)},
        {"statusText", entry.value("status_code", 0) == 0 ? "Pending" : ""},
        {"mimeType", entry.value("content_type", "")},
        {"size", entry.value("size", 0)},
        {"transferSize", entry.value("size", 0)},
        {"timing", {
            {"started", entry.value("start_time", "")},
            {"total", entry.value("duration", 0)},
        }},
        {"initiator", entry.value("initiator", "browser")},
    });
  }

  const std::size_t original_count = filtered.size();
  if (filtered.size() > static_cast<std::size_t>(limit)) {
    filtered.erase(filtered.begin(), filtered.begin() + static_cast<long>(filtered.size() - limit));
  }

  nlohmann::json summary = {
      {"totalRequests", original_count},
      {"totalSize", 0},
      {"totalTransferSize", 0},
      {"byType", nlohmann::json::object()},
      {"errors", 0},
      {"loadTime", 0},
  };
  for (const auto& entry : filtered) {
    summary["totalSize"] = summary["totalSize"].get<int>() + entry.value("size", 0);
    summary["totalTransferSize"] =
        summary["totalTransferSize"].get<int>() + entry.value("transferSize", 0);
    const std::string type = entry.value("type", "Other");
    summary["byType"][type] = summary["byType"].value(type, 0) + 1;
    if (entry.value("status", 0) >= 400) {
      summary["errors"] = summary["errors"].get<int>() + 1;
    }
    summary["loadTime"] = std::max(summary["loadTime"].get<int>(),
                                   entry["timing"].value("total", 0));
  }

  return SuccessResponse({
      {"entries", filtered},
      {"count", filtered.size()},
      {"hasMore", original_count > filtered.size()},
      {"summary", summary},
  });
}

nlohmann::json NetworkHandler::ClearNetworkLog() const {
  if (runtime_.network_store == nullptr) {
    return SuccessResponse({{"cleared", 0}});
  }
  const int count = runtime_.network_store->Count();
  runtime_.network_store->Clear();
  return SuccessResponse({{"cleared", count}});
}

}  // namespace kelpie
