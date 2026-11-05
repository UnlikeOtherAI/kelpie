#pragma once
#include <cmath>
#include <cstdint>
#include <functional>
#include <string>
#include <nlohmann/json.hpp>

namespace kelpie::windows {
struct DetachedMarkerAnchor {
  long x=0,y=0,width=0,height=0;
  std::uint32_t dpi=0;
  std::uint64_t revision=0;
  std::string run,tab,document;
  std::uint64_t generation=0;
  int action=-1;
};
inline bool SameDetachedMarkerAnchor(const DetachedMarkerAnchor& a,const DetachedMarkerAnchor& b) {
  return a.width>0 && a.height>0 && a.dpi>0 && a.revision>0 && !a.run.empty() && !a.tab.empty() && !a.document.empty() && a.generation>0 && a.action>=0 &&
    a.x==b.x && a.y==b.y && a.width==b.width && a.height==b.height && a.dpi==b.dpi && a.revision==b.revision && a.run==b.run && a.tab==b.tab && a.document==b.document &&
    a.generation==b.generation && a.action==b.action;
}
inline bool SameDetachedMarkerIdentity(const DetachedMarkerAnchor& a,const DetachedMarkerAnchor& b) {
  return !a.run.empty() && !a.tab.empty() && !a.document.empty() && a.generation>0 && a.action>=0 &&
    a.run==b.run && a.tab==b.tab && a.document==b.document && a.generation==b.generation && a.action==b.action;
}
class DetachedMarkerGeometry {
 public:
  void Lose() { if(pinned_) invalid_=true; }
  void Observe(const DetachedMarkerAnchor& current) {
    if(!SameDetachedMarkerAnchor(current,current)) { Lose(); return; }
    if(current.revision<lastRevision_) return;
    lastRevision_=current.revision;
    if(!pinned_ || current.run!=anchor_.run || current.action>anchor_.action) {
      anchor_=current; pinned_=true; invalid_=false; return;
    }
    if(current.action<anchor_.action) return;
    auto comparable=current; comparable.revision=anchor_.revision;
    if(!SameDetachedMarkerAnchor(anchor_,comparable)) invalid_=true;
  }
  bool Allows(const DetachedMarkerAnchor& current) const {
    if(!pinned_ || invalid_ || current.revision<lastRevision_ ||
       !SameDetachedMarkerIdentity(anchor_,current)) return false;
    auto comparable=current; comparable.revision=anchor_.revision;
    return SameDetachedMarkerAnchor(anchor_,comparable);
  }
 private:
  DetachedMarkerAnchor anchor_;
  bool pinned_=false,invalid_=false;
  std::uint64_t lastRevision_=0;
};inline bool DetachedMarkerActive(const nlohmann::json& shown) {
  try {
    if(shown.value("playing",false) || !shown.value("detachedMarker",false) ||
       !shown.contains("marker") || shown.contains("pointer") || shown.contains("commentary")) return false;
    const auto& marker=shown.at("marker");
    const double elapsed=shown.at("elapsedMs").get<double>();
    const double start=marker.at("startedMs").get<double>();
    const double duration=marker.value("durationMs",700.0);
    return std::isfinite(elapsed) && std::isfinite(start) && std::isfinite(duration) &&
      duration>0 && elapsed>=start && elapsed-start<duration;
  } catch(...) { return false; }
}
inline bool AuthorizeDetachedMarker(const nlohmann::json& shown,const std::function<bool()>& valid,
                                    const std::function<bool(const nlohmann::json&)>& documentGuard) {
  try { return DetachedMarkerActive(shown) && valid && valid() && documentGuard && documentGuard(shown); }
  catch(...) { return false; }
}
}
