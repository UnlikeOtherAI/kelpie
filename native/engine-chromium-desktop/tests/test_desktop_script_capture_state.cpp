#include "desktop_script_capture_state.h"
#include "desktop_capture_receipt.h"
#include "desktop_presentation_validity.h"
#include <stdexcept>
#include "kelpie/desktop_presentation_order.h"
#include <cassert>
#include <condition_variable>
#include <mutex>
#include <thread>

int main() {
  using nlohmann::json;
  using Clock=std::chrono::steady_clock;
  const auto now=Clock::now(),deadline=now+std::chrono::seconds(1);
  assert(kelpie::CaptureReceiptEligible(now,deadline,false,true,true));
  assert(!kelpie::CaptureReceiptEligible(deadline,deadline,false,true,true));
  assert(!kelpie::CaptureReceiptEligible(now,deadline,true,true,true));
  assert(!kelpie::CaptureReceiptEligible(now,deadline,false,false,true));
  assert(!kelpie::CaptureReceiptEligible(now,deadline,false,true,false));
  int calls=0;
  assert(kelpie::CaptureCompletionApproved([&] { ++calls; return true; }));
  assert(calls==1);
  assert(!kelpie::CaptureCompletionApproved([] { return false; }));
  assert(!kelpie::CaptureCompletionApproved([]()->bool { throw std::runtime_error("failure"); }));
  using Failure=kelpie::CaptureViewportFailure;
  assert(kelpie::ClassifyCaptureViewportFailure(false,"old","new")==Failure::DocumentUnavailable);
  assert(kelpie::ClassifyCaptureViewportFailure(true,"old","new")==Failure::TornFrame);
  assert(kelpie::ClassifyCaptureViewportFailure(true,"same","same")==Failure::ViewportChanged);
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
  kelpie::DesktopPresentationValidity grant([](const std::string& owner) { return owner=="owner"; });
  assert(grant.Check("owner") && !grant.Check("other"));
  grant.Close(); assert(!grant.Check("owner"));
  kelpie::DesktopPresentationValidity throwing([](const std::string&) -> bool { throw std::runtime_error("failure"); });
  assert(!throwing.Check("owner"));
  std::mutex gate_mutex; std::condition_variable gate_cv; bool entered=false, leave=false;
  kelpie::DesktopPresentationValidity synchronized([&](const std::string&) {
    std::unique_lock lock(gate_mutex); entered=true; gate_cv.notify_all();
    gate_cv.wait(lock,[&] { return leave; }); return true;
  });
  std::thread check([&] { assert(synchronized.Check("owner")); });
  { std::unique_lock lock(gate_mutex); gate_cv.wait(lock,[&] { return entered; }); }
  std::thread close([&] { synchronized.Close(); });
  { std::lock_guard lock(gate_mutex); leave=true; } gate_cv.notify_all();
  check.join(); close.join(); assert(!synchronized.Check("owner"));
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
