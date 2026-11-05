#include "desktop_script_capture_state.h"
#include "kelpie/desktop_presentation_order.h"
#include <cassert>
#include <condition_variable>
#include <mutex>
#include <thread>

int main() {
  using nlohmann::json;
  assert(kelpie::DesktopPresentationIsPlaying(json::object(),true));
  assert(!kelpie::DesktopPresentationIsPlaying({{"playing",false}},true));
  assert(!kelpie::DesktopPresentationIsPlaying(json::object(),false));
  assert(!kelpie::DesktopMovieEndpointRequired({{"capture",{{"formats",{"screenshots"}}}}}));
  assert(!kelpie::DesktopMovieEndpointRequired({{"actions",{{{"action","screenshot"}}}}}));
  assert(kelpie::DesktopMovieEndpointRequired({{"capture",{{"formats",{"gif"}}}}}));
  assert(kelpie::DesktopMovieEndpointRequired({{"capture",{{"formats",{"screenshots","video"}}}}}));
  json active={{"runId","run"},{"tabId","tab"},{"generation",7},{"documentVersion","doc"},
               {"marker",{{"startedMs",100.0},{"durationMs",700.0}}},
               {"pointer",true},{"commentary","text"}};
  const auto detached=kelpie::DetachedDesktopMarker(active,300.0);
  assert(detached.value("detachedMarker",false) && !detached.value("playing",true));
  assert(detached.contains("marker") && !detached.contains("pointer") && !detached.contains("commentary"));
  assert(detached.value("elapsedMs",0.0)==300.0);
  assert(!kelpie::DetachedDesktopMarker(active,800.0).contains("marker"));
  active.erase("documentVersion");
  assert(!kelpie::DetachedDesktopMarker(active,300.0).contains("marker"));
  std::uint64_t revision=0;
  assert(kelpie::AcceptDesktopPresentationRevision({{"_presentationRevision",std::uint64_t{2}}},revision));
  assert(!kelpie::AcceptDesktopPresentationRevision({{"_presentationRevision",std::uint64_t{1}}},revision));
  assert(!kelpie::AcceptDesktopPresentationRevision({{"_presentationRevision",std::uint64_t{2}}},revision));
  assert(!kelpie::AcceptDesktopPresentationRevision(json::object(),revision));
  assert(kelpie::AcceptDesktopPresentationRevision({{"_presentationRevision",std::uint64_t{3}}},revision));
  json retired={{"playing",false}};
  retired["_presentationRevision"]=std::uint64_t{4};
  assert(kelpie::AcceptDesktopPresentationRevision(retired,revision));
  retired["_presentationRevision"]=std::uint64_t{5}; // A late Present still remains hidden.
  retired["playing"]=kelpie::DesktopPresentationIsPlaying(retired,true);
  assert(kelpie::AcceptDesktopPresentationRevision(retired,revision));
  assert(!retired["playing"].get<bool>());
  assert(!kelpie::AcceptDesktopPresentationRevision({{"_presentationRevision",std::uint64_t{3}}},revision));
  std::mutex mutex;
  std::condition_variable changed;
  bool capturing=false, release=false;
  const kelpie::DesktopPresentationOwner old{"tab",7,"old"},current{"tab",7,"new"};
  json live={{"tabId","tab"},{"generation",7},{"documentVersion","old"},{"pointer",{{"x",1}}},{"marker",true},{"commentary","visible"}};
  json captured;
  std::thread sampler([&] {
    json snapshot;
    {
      std::unique_lock lock(mutex);
      snapshot=kelpie::SnapshotDesktopPresentation(live,old);
      capturing=true; changed.notify_one();
      changed.wait(lock,[&] { return release; });
    }
    captured=snapshot; // The blocked screenshot returns after live presentation advances.
  });
  {
    std::unique_lock lock(mutex);
    changed.wait(lock,[&] { return capturing; });
    live["pointer"]["x"]=2;
    live["documentVersion"]="new";
    assert(!kelpie::ClearRetiredDesktopPresentation(live,old));
    assert(live["pointer"]["x"]==2);
    release=true;
  }
  changed.notify_one(); sampler.join();
  assert(captured["pointer"]["x"]==1);
  assert(captured["documentVersion"]=="old");
  const auto stale=kelpie::SnapshotDesktopPresentation(live,old);
  assert(!stale.contains("pointer") && !stale.contains("marker") && !stale.contains("commentary"));
  assert(live.contains("pointer") && live.contains("marker") && live.contains("commentary"));
  assert(!kelpie::ClearRetiredDesktopPresentation(live,{"other",7,"new"}));
  assert(!kelpie::ClearRetiredDesktopPresentation(live,{"tab",8,"new"}));
  assert(kelpie::ClearRetiredDesktopPresentation(live,current));
  assert(!live.contains("pointer") && !live.contains("marker") && !live.contains("commentary"));
}
