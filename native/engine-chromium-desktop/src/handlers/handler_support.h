#pragma once

#include <algorithm>
#include <cctype>
#include <chrono>
#include <functional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "kelpie/bookmark_store.h"
#include "kelpie/console_store.h"
#include "kelpie/desktop_app.h"
#include "kelpie/error_codes.h"
#include "kelpie/handler_context.h"
#include "kelpie/history_store.h"
#include "kelpie/network_traffic_store.h"
#include "kelpie/response_helpers.h"

namespace kelpie {

struct DesktopHandlerRuntime {
  using json = nlohmann::json;
  using JsonSupplier = std::function<json()>;
  using ResizeViewport = std::function<bool(int, int)>;
  using VoidAction = std::function<void()>;

  HandlerContext* handler_context = nullptr;
  BookmarkStore* bookmark_store = nullptr;
  HistoryStore* history_store = nullptr;
  ConsoleStore* console_store = nullptr;
  NetworkTrafficStore* network_store = nullptr;
  DeviceInfoProvider* device_info_provider = nullptr;
  JsonSupplier viewport_supplier;
  JsonSupplier capabilities_supplier;
  JsonSupplier renderer_supplier;
  ResizeViewport resize_viewport;
  VoidAction reset_viewport;
  Platform platform = Platform::kLinux;
  std::string engine_name = "chromium";
};

inline std::string JsStringLiteral(const std::string& value) {
  std::ostringstream escaped;
  escaped << '"';
  for (const char ch : value) {
    switch (ch) {
      case '\\':
        escaped << "\\\\";
        break;
      case '"':
        escaped << "\\\"";
        break;
      case '\n':
        escaped << "\\n";
        break;
      case '\r':
        escaped << "\\r";
        break;
      case '\t':
        escaped << "\\t";
        break;
      default:
        escaped << ch;
        break;
    }
  }
  escaped << '"';
  return escaped.str();
}

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

inline std::string RequireString(const nlohmann::json& params, const char* key) {
  const auto it = params.find(key);
  if (it == params.end() || !it->is_string() || it->get<std::string>().empty()) {
    throw std::invalid_argument(std::string(key) + " is required");
  }
  return it->get<std::string>();
}

inline int IntOrDefault(const nlohmann::json& params, const char* key, int default_value) {
  const auto it = params.find(key);
  if (it == params.end() || !it->is_number_integer()) {
    return default_value;
  }
  return it->get<int>();
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

inline std::string Base64Encode(const std::vector<std::uint8_t>& input) {
  static constexpr char kAlphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  std::string output;
  output.reserve(((input.size() + 2U) / 3U) * 4U);

  std::size_t index = 0;
  while (index + 2U < input.size()) {
    const std::uint32_t chunk = (static_cast<std::uint32_t>(input[index]) << 16U) |
                                (static_cast<std::uint32_t>(input[index + 1U]) << 8U) |
                                static_cast<std::uint32_t>(input[index + 2U]);
    output.push_back(kAlphabet[(chunk >> 18U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 12U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 6U) & 0x3FU]);
    output.push_back(kAlphabet[chunk & 0x3FU]);
    index += 3U;
  }

  const std::size_t remaining = input.size() - index;
  if (remaining == 1U) {
    const std::uint32_t chunk = static_cast<std::uint32_t>(input[index]) << 16U;
    output.push_back(kAlphabet[(chunk >> 18U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 12U) & 0x3FU]);
    output.append("==");
  } else if (remaining == 2U) {
    const std::uint32_t chunk = (static_cast<std::uint32_t>(input[index]) << 16U) |
                                (static_cast<std::uint32_t>(input[index + 1U]) << 8U);
    output.push_back(kAlphabet[(chunk >> 18U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 12U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 6U) & 0x3FU]);
    output.push_back('=');
  }

  return output;
}

}  // namespace kelpie
