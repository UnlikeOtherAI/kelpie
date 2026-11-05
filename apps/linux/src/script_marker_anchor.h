#pragma once
#include <string>
#include <utility>

namespace kelpie::linuxapp {
struct ScriptMarkerGeometry {
  int x, y, width, height, scale, frame_width, frame_height;
  bool operator==(const ScriptMarkerGeometry&) const = default;
};
class ScriptMarkerAnchor {
 public:
  void Observe(std::string identity, ScriptMarkerGeometry geometry) {
    identity_ = std::move(identity); geometry_ = geometry;
  }
  bool Matches(const std::string& identity, ScriptMarkerGeometry geometry) const {
    return !identity_.empty() && identity_ == identity && geometry_ == geometry;
  }
  void Clear() { identity_.clear(); }
 private:
  std::string identity_;
  ScriptMarkerGeometry geometry_{};
};
}
