#include "console_handler.h"

namespace kelpie {

ConsoleHandler::ConsoleHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void ConsoleHandler::Register(DesktopRouter& router) const {
  router.Register("get-console-messages",
                  [this](const nlohmann::json& params) { return GetConsoleMessages(params); });
  router.Register("get-js-errors", [this](const nlohmann::json&) { return GetJsErrors(); });
  router.Register("clear-console", [this](const nlohmann::json&) { return ClearConsole(); });
}

nlohmann::json ConsoleHandler::GetConsoleMessages(const nlohmann::json& params) const {
  if (runtime_.console_store == nullptr) {
    return SuccessResponse({{"messages", nlohmann::json::array()}, {"count", 0}, {"hasMore", false}});
  }
  const auto level_it = params.find("level");
  const std::optional<std::string> level =
      level_it != params.end() && level_it->is_string()
          ? std::optional<std::string>(level_it->get<std::string>())
          : std::nullopt;
  const int limit = std::max(1, IntOrDefault(params, "limit", 100));
  nlohmann::json entries = ParseJsonText(runtime_.console_store->ToJson(level));
  if (entries.size() > static_cast<std::size_t>(limit)) {
    entries.erase(entries.begin(), entries.begin() + static_cast<long>(entries.size() - limit));
  }
  return SuccessResponse({
      {"messages", entries},
      {"count", entries.size()},
      {"hasMore", runtime_.console_store->Count() > static_cast<int>(entries.size())},
  });
}

nlohmann::json ConsoleHandler::GetJsErrors() const {
  if (runtime_.console_store == nullptr) {
    return SuccessResponse({{"errors", nlohmann::json::array()}, {"count", 0}});
  }
  nlohmann::json errors = ParseJsonText(runtime_.console_store->GetErrorsOnly());
  for (auto& entry : errors) {
    entry["type"] = "console-error";
  }
  return SuccessResponse({{"errors", errors}, {"count", errors.size()}});
}

nlohmann::json ConsoleHandler::ClearConsole() const {
  if (runtime_.console_store == nullptr) {
    return SuccessResponse({{"cleared", 0}});
  }
  const int count = runtime_.console_store->Count();
  runtime_.console_store->Clear();
  return SuccessResponse({{"cleared", count}});
}

}  // namespace kelpie
