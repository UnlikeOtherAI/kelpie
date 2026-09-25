#pragma once

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <limits>
#include <chrono>
#include <functional>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "kelpie/base64.h"
#include "kelpie/bookmark_store.h"
#include "kelpie/console_store.h"
#include "kelpie/desktop_app.h"
#include "kelpie/desktop_browser_control.h"
#include "kelpie/error_codes.h"
#include "kelpie/handler_context.h"
#include "kelpie/history_store.h"
#include "kelpie/js_string_literal.h"
#include "kelpie/network_traffic_store.h"
#include "kelpie/partition.h"
#include "kelpie/response_helpers.h"

namespace kelpie {

struct DesktopHandlerRuntime {
  using json = nlohmann::json;
  using JsonSupplier = std::function<json()>;
  // Implementations marshal this browser-wide operation to the native window
  // owner thread before touching CEF or shell state.
  using ResizeViewport = std::function<bool(int, int)>;
  using VoidAction = std::function<void()>;

  HandlerContext* handler_context = nullptr;
  DesktopBrowserControl* browser_control = nullptr;
  BookmarkStore* bookmark_store = nullptr;
  HistoryStore* history_store = nullptr;
  ConsoleStore* console_store = nullptr;
  NetworkTrafficStore* network_store = nullptr;
  DeviceInfoProvider* device_info_provider = nullptr;
  JsonSupplier viewport_supplier;
  JsonSupplier capabilities_supplier;
  JsonSupplier renderer_supplier;
  ResizeViewport resize_viewport;
  std::function<bool()> reset_viewport;
  std::function<BrowserControlResult(bool)> set_native_fullscreen;
  std::function<BrowserControlResult(bool*)> get_native_fullscreen;
  std::function<BrowserControlResult()> request_shutdown;
  std::function<BrowserControlResult(std::string)> set_home;
  std::function<BrowserControlResult(std::string*)> get_home;
  std::function<BrowserControlResult(std::string)> show_native_toast;
  // Optional account-aware favorites; callbacks must be thread-safe.
  std::function<nlohmann::json(const std::string&, const nlohmann::json&)> bookmark_action;
  Platform platform = Platform::kLinux;
  std::string engine_name = "chromium";
};

inline nlohmann::json ParseJsonText(const std::string& text,
                                    nlohmann::json fallback = nlohmann::json::array()) {
  if (text.empty()) {
    return fallback;
  }
  try {
    return nlohmann::json::parse(text);
  } catch (...) {
    return fallback;
  }
}

inline HandlerContext& RequireHandlerContext(const DesktopHandlerRuntime& runtime) {
  if (runtime.handler_context == nullptr) {
    throw std::runtime_error("Handler context is not configured");
  }
  return *runtime.handler_context;
}

inline DesktopBrowserControl& RequireBrowserControl(const DesktopHandlerRuntime& runtime) {
  if (runtime.browser_control == nullptr) throw std::runtime_error("Browser control is not configured");
  return *runtime.browser_control;
}

inline std::optional<std::string> OptionalTabId(const nlohmann::json& params) {
  const auto it = params.find("tabId");
  if (it == params.end()) return std::nullopt;
  if (!it->is_string() || it->get<std::string>().empty()) throw std::invalid_argument("tabId must be a non-empty string");
  return it->get<std::string>();
}

inline std::optional<std::uint64_t> OptionalGeneration(const nlohmann::json& params) {
  const auto it = params.find("generation");
  if (it == params.end()) return std::nullopt;
  if (it->is_number_unsigned()) return it->get<std::uint64_t>();
  if (it->is_number_integer() && it->get<std::int64_t>() >= 0) {
    return static_cast<std::uint64_t>(it->get<std::int64_t>());
  }
  throw std::invalid_argument("generation must be a non-negative integer");
}

inline nlohmann::json TabJson(const TabSnapshot& tab) {
  nlohmann::json json = {{"id", tab.id}, {"generation", tab.generation}, {"url", tab.url},
                         {"title", tab.title}, {"active", tab.active},
                         {"isLoading", tab.is_loading}, {"canGoBack", tab.can_go_back},
                         {"canGoForward", tab.can_go_forward}};
  // The partition fields are omitted rather than nulled for a tab in the
  // default shared store, so an existing consumer sees the same object it
  // always saw.
  if (tab.name) json["name"] = *tab.name;
  if (tab.partition) json["partition"] = *tab.partition;
  if (tab.persistent) json["persistent"] = *tab.persistent;
  return json;
}

inline nlohmann::json ControlError(const BrowserControlResult& result) {
  nlohmann::json response =
      ErrorResponse(result.error_code.empty() ? "WEBVIEW_ERROR" : result.error_code,
                    result.message.empty() ? "Browser operation failed" : result.message,
                    result.operation_may_have_completed
                        ? nlohmann::json{{"operationMayHaveCompleted", true}}
                        : nlohmann::json::object());
  // PARTITION_UNSUPPORTED carries `reason`, `hint` and `activeEngine` as direct
  // siblings of code and message — the shape macOS already emits and the shape
  // docs/api/partitions.md documents, not a nested diagnostics bag.
  if (result.details.is_object()) {
    for (auto it = result.details.begin(); it != result.details.end(); ++it) {
      response["error"][it.key()] = it.value();
    }
  }
  return response;
}

// `new-tab`'s optional naming and isolation fields. Throws std::invalid_argument
// for a malformed request and returns the INVALID_PARTITION body for a string
// the shared validator rejects, so the caller can return one or the other.
inline std::optional<nlohmann::json> ReadPartitionFields(const nlohmann::json& params,
                                                         NewTabRequest* request) {
  const auto name = params.find("name");
  if (name != params.end() && !name->is_null()) {
    if (!name->is_string()) throw std::invalid_argument("name must be a string");
    const std::string value = name->get<std::string>();
    if (value.size() > kMaxTabNameLength) {
      throw std::invalid_argument("name must be at most 200 characters");
    }
    request->name = value;
  }
  const auto persistent = params.find("persistent");
  if (persistent != params.end() && !persistent->is_null()) {
    if (!persistent->is_boolean()) throw std::invalid_argument("persistent must be a boolean");
    request->persistent = persistent->get<bool>();
  }
  const auto partition = params.find("partition");
  if (partition == params.end() || partition->is_null()) return std::nullopt;
  if (!partition->is_string()) throw std::invalid_argument("partition must be a string");
  const std::string value = partition->get<std::string>();
  const PartitionValidation validation = ValidatePartition(value);
  if (!validation.ok) {
    return ErrorResponse(ErrorCode::kInvalidPartition,
                         "Invalid partition \"" + value + "\": " +
                             PartitionErrorMessage(validation.reason));
  }
  request->partition = value;
  return std::nullopt;
}

inline std::string RequireString(const nlohmann::json& params, const char* key, bool allow_empty = false) {
  const auto it = params.find(key);
  if (it == params.end() || !it->is_string() || (!allow_empty && it->get<std::string>().empty())) {
    throw std::invalid_argument(std::string(key) + " is required");
  }
  return it->get<std::string>();
}

// nlohmann narrows a whole number to `int` with a silent static_cast, so
// 4294967297 arrives as 1 and satisfies any range check. Widening first is what
// makes the bounds mean anything.
inline std::int64_t WideInteger(const nlohmann::json& value) {
  if (!value.is_number_unsigned()) return value.get<std::int64_t>();
  const auto raw = value.get<std::uint64_t>();
  constexpr auto kCeiling = static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
  return raw > kCeiling ? std::numeric_limits<std::int64_t>::max() : static_cast<std::int64_t>(raw);
}

inline int IntOrDefault(const nlohmann::json& params, const char* key, int default_value) {
  const auto it = params.find(key);
  if (it == params.end()) return default_value;
  if (!it->is_number_integer()) {
    throw std::invalid_argument(std::string(key) + " must be an integer");
  }
  const std::int64_t value = WideInteger(*it);
  if (value < std::numeric_limits<int>::min() || value > std::numeric_limits<int>::max()) {
    throw std::invalid_argument(std::string(key) + " is out of range");
  }
  return static_cast<int>(value);
}

inline double RequireNumber(const nlohmann::json& params, const char* key) {
  const auto it = params.find(key);
  if (it == params.end() || !it->is_number()) {
    throw std::invalid_argument(std::string(key) + " must be a number");
  }
  return it->get<double>();
}

inline int RequireBoundedInteger(const nlohmann::json& params, const char* key, int minimum,
                                 int maximum) {
  const auto it = params.find(key);
  if (it == params.end() || !it->is_number_integer()) {
    throw std::invalid_argument(std::string(key) + " must be an integer");
  }
  const std::int64_t value = WideInteger(*it);
  if (value < minimum || value > maximum) {
    throw std::invalid_argument(std::string(key) + " must be between " + std::to_string(minimum) +
                                " and " + std::to_string(maximum));
  }
  return static_cast<int>(value);
}

inline std::optional<nlohmann::json> RejectBrowserWideTab(const nlohmann::json& params) {
  if (params.contains("tabId") || params.contains("generation")) {
    return ErrorResponse(ErrorCode::kInvalidParams,
                         "This browser-wide method does not accept tabId or generation");
  }
  return std::nullopt;
}

inline DesktopBrowserControl::Timeout ControlTimeout(const nlohmann::json& params) {
  const int value = IntOrDefault(params, "timeout", 10000);
  return std::chrono::milliseconds(std::clamp(value, 1, 30000));
}

inline BrowserControlResult EvaluateForTab(const DesktopHandlerRuntime& runtime,
                                           const nlohmann::json& params,
                                           const std::string& expression,
                                           nlohmann::json* value) {
  TabLease lease;
  BrowserControlResult result = RequireBrowserControl(runtime).ResolveTab(
      OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
  if (!result.ok) return result;
  return RequireBrowserControl(runtime).Evaluate(lease, expression, value, ControlTimeout(params));
}

inline bool BoolOrDefault(const nlohmann::json& params, const char* key, bool default_value) {
  const auto it = params.find(key);
  if (it == params.end() || !it->is_boolean()) {
    return default_value;
  }
  return it->get<bool>();
}

inline nlohmann::json Unsupported(const std::string& method) {
  return ErrorResponse(ErrorCode::kPlatformNotSupported,
                       method + " is not supported on desktop Chromium");
}

inline nlohmann::json InvalidParams(const std::string& message) {
  return ErrorResponse(ErrorCode::kInvalidParams, message);
}

inline std::int64_t NowMillis() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return std::chrono::duration_cast<std::chrono::milliseconds>(now).count();
}

inline std::string ToUpper(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::toupper(ch));
  });
  return value;
}

}  // namespace kelpie
