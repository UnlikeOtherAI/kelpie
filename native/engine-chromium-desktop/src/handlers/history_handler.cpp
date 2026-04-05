#include "history_handler.h"

namespace kelpie {

HistoryHandler::HistoryHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void HistoryHandler::Register(DesktopRouter& router) const {
  router.Register("history-list", [this](const nlohmann::json& params) { return List(params); });
  router.Register("history-clear", [this](const nlohmann::json&) { return Clear(); });

  router.Register("get-history", [this](const nlohmann::json& params) { return List(params); });
  router.Register("clear-history", [this](const nlohmann::json&) { return Clear(); });
}

nlohmann::json HistoryHandler::List(const nlohmann::json& params) const {
  if (runtime_.history_store == nullptr) {
    return SuccessResponse({{"entries", nlohmann::json::array()}, {"total", 0}});
  }
  nlohmann::json entries = ParseJsonText(runtime_.history_store->ToJson());
  const int limit = std::max(1, IntOrDefault(params, "limit", 100));
  if (entries.size() > static_cast<std::size_t>(limit)) {
    entries.erase(entries.begin() + limit, entries.end());
  }
  return SuccessResponse({{"entries", entries}, {"total", runtime_.history_store->Count()}});
}

nlohmann::json HistoryHandler::Clear() const {
  if (runtime_.history_store != nullptr) {
    runtime_.history_store->Clear();
  }
  return SuccessResponse({{"cleared", true}});
}

}  // namespace kelpie
