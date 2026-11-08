#pragma once

#include <cstring>
#include <new>
#include <optional>
#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/bookmark_store.h"
#include "kelpie/console_store.h"
#include "kelpie/history_store.h"
#include "kelpie/network_traffic_store.h"
#include "store_support.h"

struct KelpieBookmarkStore {
  kelpie::BookmarkStore store;
};

struct KelpieHistoryStore {
  kelpie::HistoryStore store;
};

struct KelpieNetworkTrafficStore {
  kelpie::NetworkTrafficStore store;
};

struct KelpieConsoleStore {
  kelpie::ConsoleStore store;
};

namespace kelpie::state_c_api_internal {

using json = nlohmann::json;

inline const char* SafeCString(const char* value) {
  return value == nullptr ? "" : value;
}

inline char* CopyString(const std::string& value) {
  char* buffer = new (std::nothrow) char[value.size() + 1];
  if (buffer == nullptr) {
    return nullptr;
  }
  std::memcpy(buffer, value.c_str(), value.size() + 1);
  return buffer;
}

inline StringMap ParseHeadersObject(const json& parsed) {
  StringMap headers;
  if (!parsed.is_object()) {
    return headers;
  }
  for (auto it = parsed.begin(); it != parsed.end(); ++it) {
    if (it.value().is_string()) {
      headers[it.key()] = it.value().get<std::string>();
    }
  }
  return headers;
}

inline StringMap ParseHeadersJson(const char* json_text) {
  return ParseHeadersObject(store_support::ParseJson(SafeCString(json_text)));
}

inline std::optional<TrafficEntry> ParseTrafficEntry(const char* json_text) {
  const json parsed = store_support::ParseJson(SafeCString(json_text));
  if (!parsed.is_object()) {
    return std::nullopt;
  }

  const std::string url = store_support::StringOrDefault(parsed, {"url"});
  const std::string method = store_support::StringOrDefault(parsed, {"method"});
  if (url.empty() || method.empty()) {
    return std::nullopt;
  }

  return TrafficEntry{
      store_support::StringOrDefault(parsed, {"id"}, store_support::GenerateUuidV4()),
      method,
      url,
      store_support::IntOrDefault(parsed, {"status_code", "statusCode"}),
      store_support::StringOrDefault(parsed, {"content_type", "contentType"}),
      parsed.contains("request_headers") ? ParseHeadersObject(parsed["request_headers"])
                                         : ParseHeadersObject(parsed.value("requestHeaders", json::object())),
      parsed.contains("response_headers") ? ParseHeadersObject(parsed["response_headers"])
                                          : ParseHeadersObject(parsed.value("responseHeaders", json::object())),
      store_support::StringOrDefault(parsed, {"request_body", "requestBody"}),
      store_support::StringOrDefault(parsed, {"response_body", "responseBody"}),
      store_support::StringOrDefault(parsed, {"start_time", "startTime"},
                                     store_support::CurrentIso8601Utc()),
      store_support::IntOrDefault(parsed, {"duration"}),
      store_support::Int64OrDefault(parsed, {"size"}),
  };
}

inline std::optional<ConsoleEntry> ParseConsoleEntry(const char* json_text) {
  const json parsed = store_support::ParseJson(SafeCString(json_text));
  if (!parsed.is_object()) {
    return std::nullopt;
  }

  const std::optional<ConsoleLevel> level =
      ConsoleStore::LevelFromString(store_support::StringOrDefault(parsed, {"level"}));
  if (!level.has_value()) {
    return std::nullopt;
  }

  return ConsoleEntry{
      store_support::StringOrDefault(parsed, {"id"}, store_support::GenerateUuidV4()),
      *level,
      store_support::StringOrDefault(parsed, {"text"}),
      store_support::StringOrDefault(parsed, {"source"}),
      store_support::IntOrDefault(parsed, {"line"}),
      store_support::IntOrDefault(parsed, {"column"}),
      store_support::StringOrDefault(parsed, {"timestamp"}, store_support::CurrentIso8601Utc()),
      store_support::OptionalValue<std::string>(parsed, "stack_trace"),
  };
}

}  // namespace kelpie::state_c_api_internal
