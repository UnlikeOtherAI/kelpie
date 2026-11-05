#pragma once
#include <cstdint>
#include <nlohmann/json.hpp>

namespace kelpie {
// Called on the native consumer's serialized thread or under its mutex.
inline bool AcceptDesktopPresentationRevision(const nlohmann::json& state, std::uint64_t& last) {
  auto revision=state.find("_presentationRevision");
  if(revision==state.end() || !revision->is_number_unsigned()) return false;
  const auto next=revision->get<std::uint64_t>();
  if(next<=last) return false;
  last=next;
  return true;
}
}