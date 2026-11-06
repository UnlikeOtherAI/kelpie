#pragma once

#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <nlohmann/json.hpp>

namespace kelpie {
// Parse only the bounded event fields needed by the owned-fixture probe.
// The caller must validate the browser, origin and lease before calling this.
struct DesktopTestStreamEvent {
  int session = 0;
  double timestamp = 0;
  std::string encoded;
};

inline std::optional<DesktopTestStreamEvent> ParseDesktopTestStreamEvent(const std::string& input) {
  constexpr std::size_t kMaxEnvelope = 3 * 1024 * 1024;
  constexpr std::size_t kMaxEncoded = 2 * 1024 * 1024;
  if (input.empty() || input.size() > kMaxEnvelope) return std::nullopt;
  try {
    auto value = nlohmann::json::parse(input);
    if (!value.is_object() || !value.contains("sessionId") || !value["sessionId"].is_number_integer() ||
        !value.contains("metadata") || !value["metadata"].is_object() ||
        !value["metadata"].contains("timestamp") || !value["metadata"]["timestamp"].is_number() ||
        !value.contains("data") || !value["data"].is_string()) return std::nullopt;
    const auto session = value["sessionId"].get<std::int64_t>();
    const auto timestamp = value["metadata"]["timestamp"].get<double>();
    auto encoded = value["data"].get<std::string>();
    if (session <= 0 || session > 2147483647 || !std::isfinite(timestamp) || timestamp < 0 ||
        encoded.empty() || encoded.size() > kMaxEncoded) return std::nullopt;
    return DesktopTestStreamEvent{static_cast<int>(session), timestamp, std::move(encoded)};
  } catch (...) { return std::nullopt; }
}
}  // namespace kelpie
