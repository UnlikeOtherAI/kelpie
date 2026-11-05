#pragma once
#include <nlohmann/json.hpp>
#include <cstdint>
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
