#include "console_handler.h"

namespace kelpie {

ConsoleHandler::ConsoleHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void ConsoleHandler::Register(DesktopRouter& router) const {
  router.Register("get-console-messages",
                  [this](const nlohmann::json& params) { return GetConsoleMessages(params); });
  router.Register("get-js-errors", [this](const nlohmann::json& p) { return GetJsErrors(p); });
  router.Register("clear-console", [this](const nlohmann::json& p) { if (const auto invalid = RejectBrowserWideTab(p)) return *invalid; return ClearConsole(); });
}

nlohmann::json ConsoleHandler::GetConsoleMessages(const nlohmann::json& params) const {
  std::optional<std::string> tab_id;
  if (const auto invalid = DiagnosticScope(runtime_, params, &tab_id)) return *invalid;
  if (runtime_.console_store == nullptr) {
    return Unsupported("get-console-messages");
  }
  const auto level_it = params.find("level");
  const std::optional<std::string> level =
      level_it != params.end() && level_it->is_string()
          ? std::optional<std::string>(level_it->get<std::string>())
          : std::nullopt;
  const int limit = std::max(0, IntOrDefault(params, "limit", 100));
  nlohmann::json entries = ParseJsonText(runtime_.console_store->ToJson(level));
  const auto since = DiagnosticSince(params);
  entries.erase(std::remove_if(entries.begin(), entries.end(), [&](const auto& entry) {
    return (tab_id && entry.value("tabId", "") != *tab_id) ||
           (since && ParseDiagnosticTimestamp(entry.value("timestamp", "")).value_or(0) < *since);
  }), entries.end());
  const bool has_more = entries.size() > static_cast<std::size_t>(limit);
  if (has_more) {
    entries.erase(entries.begin(), entries.begin() + static_cast<long>(entries.size() - limit));
  }
  return SuccessResponse({
      {"messages", entries},
      {"count", entries.size()},
      {"hasMore", has_more},
  });
}

nlohmann::json ConsoleHandler::GetJsErrors(const nlohmann::json& params) const {
  std::optional<std::string> tab_id;
  if (const auto invalid = DiagnosticScope(runtime_, params, &tab_id)) return *invalid;
  if (runtime_.console_store == nullptr) {
    return Unsupported("get-js-errors");
  }
  nlohmann::json errors = ParseJsonText(runtime_.console_store->GetErrorsOnly());
  if (tab_id) {
    errors.erase(std::remove_if(errors.begin(), errors.end(), [&tab_id](const auto& entry) {
      return entry.value("tabId", "") != *tab_id;
    }), errors.end());
  }
  for (auto& entry : errors) {
    entry["type"] = "console-error";
  }
  return SuccessResponse({{"errors", errors}, {"count", errors.size()}});
}

nlohmann::json ConsoleHandler::ClearConsole() const {
  if (runtime_.console_store == nullptr) {
    return Unsupported("clear-console");
  }
  const int count = runtime_.console_store->Count();
  runtime_.console_store->Clear();
  return SuccessResponse({{"cleared", count}});
}

}  // namespace kelpie
