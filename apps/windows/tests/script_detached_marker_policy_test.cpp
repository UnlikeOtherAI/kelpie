#include "script_detached_marker_policy.h"
#include <cassert>
#include <limits>
#include <stdexcept>

int main() {
  using nlohmann::json;
  using kelpie::windows::DetachedMarkerActive;
  using kelpie::windows::DetachedMarkerAnchor;
  using kelpie::windows::SameDetachedMarkerAnchor;
  json shown={{"playing",false},{"detachedMarker",true},{"elapsedMs",120.0},
    {"marker",{{"startedMs",100.0},{"durationMs",700.0}}}};
  assert(DetachedMarkerActive(shown));
  const auto allow=[] { return true; };
  const auto document=[](const json&) { return true; };
  assert(kelpie::windows::AuthorizeDetachedMarker(shown,allow,document));
  assert(!kelpie::windows::AuthorizeDetachedMarker(shown,{},document));
  assert(!kelpie::windows::AuthorizeDetachedMarker(shown,[] { return false; },document));
  assert(!kelpie::windows::AuthorizeDetachedMarker(shown,[]()->bool { throw std::runtime_error("x"); },document));
  assert(!kelpie::windows::AuthorizeDetachedMarker(shown,allow,[](const json&)->bool { throw std::runtime_error("x"); }));
  shown["elapsedMs"]=800.0;assert(!DetachedMarkerActive(shown));
  shown["elapsedMs"]=99.0;assert(!DetachedMarkerActive(shown));
  shown["elapsedMs"]=120.0;shown["pointer"]=json::object();assert(!DetachedMarkerActive(shown));
  shown.erase("pointer");shown["commentary"]=json::object();assert(!DetachedMarkerActive(shown));
  shown.erase("commentary");shown["playing"]=true;assert(!DetachedMarkerActive(shown));
  shown["playing"]=false;shown["marker"]["durationMs"]=0;assert(!DetachedMarkerActive(shown));
  shown["marker"]["durationMs"]=std::numeric_limits<double>::quiet_NaN();assert(!DetachedMarkerActive(shown));
  shown["marker"].erase("durationMs");assert(DetachedMarkerActive(shown));
  const DetachedMarkerAnchor a{10,20,800,600,144,7,"run","tab","doc",4,2},same{10,20,800,600,144,7,"run","tab","doc",4,2};
  assert(SameDetachedMarkerAnchor(a,same));
  assert(!SameDetachedMarkerAnchor(a,{11,20,800,600,144,7,"run","tab","doc",4,2}));
  assert(!SameDetachedMarkerAnchor(a,{10,20,801,600,144,7,"run","tab","doc",4,2}));
  assert(!SameDetachedMarkerAnchor(a,{10,20,800,600,96,7,"run","tab","doc",4,2}));
  assert(!SameDetachedMarkerAnchor(a,{10,20,800,600,144,8,"run","tab","doc",4,2}));
  assert(!SameDetachedMarkerAnchor(a,{10,20,800,600,144,7,"other","tab","doc",4,2}));
  assert(!SameDetachedMarkerAnchor(a,{10,20,800,600,144,7,"run","tab","other",4,2}));
  assert(!SameDetachedMarkerAnchor(a,{10,20,800,600,144,7,"run","tab","doc",5,2}));
  assert(!SameDetachedMarkerAnchor(a,{10,20,800,600,144,7,"run","tab","doc",4,3}));
  assert(!SameDetachedMarkerAnchor({},{}));
  kelpie::windows::DetachedMarkerGeometry geometry;
  assert(!geometry.Allows(a));
  geometry.Observe(a);
  auto later=a;later.revision=8;
  assert(geometry.Allows(later));
  auto stale=later;stale.revision=6;stale.x++;
  geometry.Observe(stale);assert(geometry.Allows(later));
  auto moved=later;moved.x++;
  geometry.Observe(moved);assert(!geometry.Allows(later));
  geometry.Observe(later);assert(!geometry.Allows(later));
  auto next=later;next.action=3;next.revision=9;
  geometry.Observe(next);assert(geometry.Allows(next));
  auto oldAgain=later;oldAgain.revision=10;
  geometry.Observe(oldAgain);assert(!geometry.Allows(oldAgain));
  next.revision=11;assert(geometry.Allows(next));
  geometry.Lose();assert(!geometry.Allows(next));
  geometry.Observe(next);assert(!geometry.Allows(next));
  next.run="new";next.revision=12;geometry.Observe(next);assert(geometry.Allows(next));
}
