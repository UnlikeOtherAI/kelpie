#include "kelpie/native_extension_schema.h"
#include <set>
#include "browser_contract.h"
namespace kelpie {
nlohmann::json NativeExtensionInputSchema(std::string_view endpoint) {
  static const auto schemas = nlohmann::json::parse(browser_assets::extension_schemas);
  const auto match = schemas.find(std::string(endpoint));
  // A missing contract is unsupported, never an empty permissive or empty-object schema.
  return match == schemas.end() ? nlohmann::json(false) : *match;
}

bool NativeExtensionMutates(std::string_view endpoint) {
  static const std::set<std::string> reads = {
    "get-links", "get-current-url", "get-home", "bookmarks-list", "history-list", "screenshot", "screenshot-annotated",
    "get-dom", "query-selector", "query-selector-all", "get-element-text", "get-attributes",
    "get-device-info", "get-capabilities", "get-tabs", "get-network-log", "get-console-messages", "get-js-errors",
    "get-dialog", "get-storage", "get-cookies", "get-fullscreen", "get-renderer", "get-viewport-preset", "get-viewport",
    "get-debug-overlay", "get-tap-calibration", "get-ai-status", "ai-status", "ai-models", "ai-endpoints", "ai-endpoint-health",
    "get-partitions", "find-element", "find-button", "find-link", "find-input", "get-page-text", "get-visible-elements",
    "get-form-state", "get-accessibility-tree", "get-input-state", "get-clipboard", "wait-for-element", "wait-for-navigation"
  };
  return reads.count(std::string(endpoint)) == 0;
}

}
