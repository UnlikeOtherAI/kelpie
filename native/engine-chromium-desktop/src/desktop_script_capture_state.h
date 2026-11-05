#pragma once
#include <nlohmann/json.hpp>
#include "kelpie/desktop_script_capture.h"
#include <cstdint>
#include <cmath>
#include <string>

namespace kelpie {
struct DesktopPresentationOwner {
  std::string tab;
  std::uint64_t generation;
  std::string document;
};
inline bool DesktopPresentationOwnedBy(const nlohmann::json& state, const DesktopPresentationOwner& owner) {
  return state.value("tabId",std::string())==owner.tab &&
    state.value("generation",std::uint64_t{})==owner.generation &&
    state.value("documentVersion",std::string())==owner.document;
}
inline bool DesktopPresentationIsPlaying(const nlohmann::json& state, bool running) {
  return running && state.value("playing",true);
}
inline void ClearDesktopPresentationContent(nlohmann::json& state) {
  state.erase("marker"); state.erase("pointer"); state.erase("commentary");
}
inline bool DesktopMovieEndpointRequired(const nlohmann::json& script) {
  if (!script.contains("capture")) return false;
  for (const auto& format : script.at("capture").at("formats"))
    if (format == "gif" || format == "video") return true;
  return false;
}
inline nlohmann::json DetachedDesktopMarker(const nlohmann::json& state, double elapsed) {
  if (!state.contains("runId") || !state.contains("marker") || !state.contains("tabId") || !state.contains("generation") ||
      !state.contains("documentVersion")) return {{"playing", false}};
  const auto& marker = state.at("marker");
  if (elapsed >= marker.value("startedMs", 0.0) + marker.value("durationMs", 700.0))
    return {{"playing", false}};
  auto detached = state;
  detached.erase("pointer"); detached.erase("commentary");
  detached["playing"] = false; detached["detachedMarker"] = true; detached["elapsedMs"] = elapsed;
  return detached;
}
inline DesktopScriptFramePurpose DesktopTerminalTicketPurpose(const nlohmann::json& state) {
  return state.contains("marker") ? DesktopScriptFramePurpose::TerminalClear : DesktopScriptFramePurpose::Ordinary;
}
inline nlohmann::json DesktopTerminalMarkerIdentity(const nlohmann::json& state) {
  if (!state.contains("runId") || !state["runId"].is_string() || state["runId"].get<std::string>().empty() ||
      !state.contains("tabId") || !state["tabId"].is_string() || state["tabId"].get<std::string>().empty() ||
      !state.contains("generation") || !state["generation"].is_number_unsigned() ||
      !state.contains("documentVersion") || !state["documentVersion"].is_string() ||
      state["documentVersion"].get<std::string>().empty() || !state.contains("marker") || !state["marker"].is_object())
    return nullptr;
  const auto& marker=state["marker"];
  if (!marker.contains("actionIndex") || !marker["actionIndex"].is_number_integer() ||
      !marker.contains("startedMs") || !marker["startedMs"].is_number() ||
      !marker.contains("durationMs") || !marker["durationMs"].is_number()) return nullptr;
  const double start=marker["startedMs"], duration=marker["durationMs"];
  if (marker["actionIndex"].get<int>()<0 || !std::isfinite(start) || !std::isfinite(duration) || duration<=0) return nullptr;
  return nlohmann::json::array({state["runId"],state["tabId"],state["generation"],state["documentVersion"],marker});
}
// Call with the presentation mutex held. The returned frame is independent.
inline nlohmann::json SnapshotDesktopPresentation(const nlohmann::json& live, const DesktopPresentationOwner& owner) {
  auto shown=live;
  if(!DesktopPresentationOwnedBy(shown,owner)) ClearDesktopPresentationContent(shown);
  return shown;
}
// A retired capture cannot clear a presentation already owned by a newer document.
inline bool ClearRetiredDesktopPresentation(nlohmann::json& live, const DesktopPresentationOwner& owner) {
  if(!DesktopPresentationOwnedBy(live,owner)) return false;
  ClearDesktopPresentationContent(live);
  return true;
}
}
