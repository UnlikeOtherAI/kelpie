#pragma once
#include <cstdint>
#include <string>
#include <utility>

namespace kelpie::linuxapp {
struct ScriptMarkerGeometry {
  int x, y, width, height, scale, frame_width, frame_height;
  bool operator==(const ScriptMarkerGeometry&) const = default;
};
class ScriptMarkerAnchor {
 public:
  void Observe(std::uint64_t revision, const std::string& identity, ScriptMarkerGeometry geometry) {
    if (revision < revision_) return;
    revision_ = revision;
    if (identity_ != identity) { identity_ = identity; geometry_ = geometry; invalid_ = false; }
    else if (!(geometry_ == geometry)) invalid_ = true;
  }
  void Invalidate(std::uint64_t revision, const std::string& identity) {
    if (revision < revision_) return;
    revision_ = revision; identity_ = identity; invalid_ = true;
  }
  bool Matches(std::uint64_t revision, const std::string& identity, ScriptMarkerGeometry geometry) const {
    return revision >= revision_ && !identity_.empty() && !invalid_ && identity_ == identity && geometry_ == geometry;
  }
  void Clear() { identity_.clear(); invalid_ = true; }
 private:
  std::uint64_t revision_ = 0;
  std::string identity_;
  ScriptMarkerGeometry geometry_{};
  bool invalid_ = true;
};
}
