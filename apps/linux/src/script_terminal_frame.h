#pragma once
#include <cmath>
#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {
struct ScriptTerminalFrameProof {
  nlohmann::json identity;
  bool clear = false;
};
inline ScriptTerminalFrameProof TerminalFrameProof(const nlohmann::json& shown, double elapsed) {
  if (!shown.contains("runId") || !shown["runId"].is_string() || !shown.contains("tabId") ||
      !shown.contains("generation") || !shown.contains("documentVersion") ||
      !shown.contains("marker") || !shown["marker"].is_object() || !shown.contains("viewportWidth") ||
      !shown.contains("viewportHeight") || !shown.contains("visualViewport")) return {};
  const auto& marker=shown["marker"];
  if (!marker.contains("startedMs") || !marker["startedMs"].is_number() ||
      !marker.contains("durationMs") || !marker["durationMs"].is_number()) return {};
  const double start=marker["startedMs"], duration=marker["durationMs"];
  if (!std::isfinite(start) || !std::isfinite(duration) || duration<=0) return {};
  return {nlohmann::json::array({shown["runId"],shown["tabId"],shown["generation"],shown["documentVersion"],
      marker,shown["viewportWidth"],shown["viewportHeight"],shown["visualViewport"]}),
      elapsed>=start+duration};
}
inline bool MatchingTerminalFrameProof(const ScriptTerminalFrameProof& observed,
                                       const ScriptTerminalFrameProof& admitted) {
  return observed.clear && admitted.clear && !observed.identity.is_null() && observed.identity==admitted.identity;
}
}
