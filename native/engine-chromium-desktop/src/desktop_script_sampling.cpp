#if defined(KELPIE_TEST_G08_ROI_WITNESS)
#include "desktop_test_g08_scope.h"
#endif
#include "desktop_script_runtime.h"
#include "desktop_script_coordinates.h"
#include "desktop_script_capture_state.h"
#include "desktop_capture_stage_timing.h"
#include <stdexcept>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace kelpie {
namespace {
void ViewportDiagnostic(const char* fence,const nlohmann::json& before,const nlohmann::json& after) {
  const char* enabled=std::getenv("KELPIE_CAPTURE_VIEWPORT_DIAGNOSTICS");
  if (!enabled || std::strcmp(enabled,"1")!=0) return;
  const nlohmann::json facts={{"fence",fence},{"before",ScriptCaptureViewportFacts(before)},
                    {"after",ScriptCaptureViewportFacts(after)}};
  std::fprintf(stderr,"KELPIE_CAPTURE_VIEWPORT_DIAGNOSTIC %s\n",facts.dump().c_str());
}
}
void DesktopScriptHandler::Impl::StepScreenshot(int index, bool png, const std::string& document, DesktopScriptFramePurpose purpose) {
  std::unique_lock lock(mutex);
  if (purpose==DesktopScriptFramePurpose::TerminalClear) purpose=DesktopTerminalTicketPurpose(presentation);
  requested_step = index; requested_step_png=png; requested_step_document=document; requested_purpose=purpose;
  requested_terminal_identity=purpose==DesktopScriptFramePurpose::TerminalClear ? DesktopTerminalMarkerIdentity(presentation) : Json(nullptr);
  const auto ticket=++requested_ticket;
  changed.notify_all();
  changed.wait_for(lock, std::chrono::seconds(10), [this, ticket] {
    return completed_ticket >= ticket || sampler_done || !capture_error.empty() || abort->load();
  });
  if (completed_ticket < ticket && !abort->load()) {
    if(capture_error.empty()) capture_error=document.empty()?"CAPTURE_STEP_FAILED":"CAPTURE_EVIDENCE_TIMEOUT";
    throw std::runtime_error("CAPTURE_STEP_FAILED");
  }
}
void DesktopScriptHandler::Impl::Sample(TabLease lease, Json options) {
  DesktopCaptureStageTiming stage_timing;
#if defined(KELPIE_TEST_G08_ROI_WITNESS)
  TestG08Scope test_scope;
  bool test_scope_intact = true, test_scope_started = false;
  Json test_scope_viewport;
  std::string test_scope_document;
#endif
  std::unique_ptr<DesktopScriptCapture> encoder;
  int initial_width = 0, initial_height = 0;
  Json previous_viewport;
  std::string previous_document;
  const std::string viewport_expression="(()=>{const v=window.visualViewport;return {width:innerWidth,height:innerHeight,visualViewport:{offsetLeft:v?.offsetLeft??0,offsetTop:v?.offsetTop??0,width:v?.width??innerWidth,height:v?.height??innerHeight,scale:v?.scale??1}}})()";
  std::string first_document;
  std::size_t dropped = 0;
  bool partial = false;
  std::string reason;
  try {
    if(!config.revalidate || !config.revalidate(owner)) {
      grant_revoked.store(true); abort->store(true); throw std::runtime_error("CAPTURE_AUTHORIZATION_REVOKED");
    }
    encoder = config.capture(options, run_id, owner);
    if (!encoder) throw std::runtime_error("CAPTURE_UNAVAILABLE");
    const bool movies=std::any_of(options["formats"].begin(),options["formats"].end(),[](const Json& format){return format=="gif" || format=="video";});
    const int fps = options.value("fps", 15);
    const int duration = options.value("maxDurationMs", 60000);
    auto next = Clock::now();
    const auto interval=std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(1.0/fps));
    while (!stop_sampler.load() && !abort->load()) {
      if(!config.revalidate || !config.revalidate(owner)) { grant_revoked.store(true); abort->store(true); partial=true; break; }
      if (Elapsed() >= duration) throw std::runtime_error("CAPTURE_DURATION_EXCEEDED");
      const auto acquisition=Clock::now();
      const auto timing_start=stage_timing.Now();
      BrowserNavigationState before, after;
      auto result = engine.GetNavigationState(lease, &before, std::chrono::seconds(2));
      const auto timing_pre_nav=stage_timing.Now();
      if (!result.ok) throw std::runtime_error("CAPTURE_DOCUMENT_UNAVAILABLE");
      Json viewport;
      result = engine.EvaluateBrowserControl(lease, viewport_expression, &viewport, std::chrono::seconds(2));
      if (!result.ok || !viewport.is_object()) throw std::runtime_error("CAPTURE_VIEWPORT_UNAVAILABLE");
      const int width = viewport.value("width", 0), height = viewport.value("height", 0);
      if (width <= 0 || height <= 0) throw std::runtime_error("CAPTURE_VIEWPORT_UNAVAILABLE");
      if (initial_width == 0) { initial_width = width; initial_height = height; first_document = before.tab.document_version; }
      if (width != initial_width || height != initial_height) {
        ViewportDiagnostic("initial-size",{{"width",initial_width},{"height",initial_height}},viewport);
        throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
      }
      // Scrollbar gutters may change visible size without changing the surface.
      // Pan/scale remain fenced within a document, and every surface still has
      // an exact before/after five-metric check below.
      if(previous_viewport.is_object() && !ScriptCaptureViewportCompatible(previous_viewport,viewport,
          previous_document==before.tab.document_version)) {
        ViewportDiagnostic("inter-frame",previous_viewport,viewport);
        throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
      }
      previous_viewport=viewport; previous_document=before.tab.document_version;
      const DesktopPresentationOwner sample_owner{lease.id,lease.generation,before.tab.document_version};
      // The encoder receives this snapshot while live presentation continues.
      Json shown;
      int step = -1, index = -1; bool png=false; std::string expected_document; std::uint64_t ticket=0;
      DesktopScriptFramePurpose purpose=DesktopScriptFramePurpose::Ordinary; Json terminal_identity;
      {
        std::lock_guard lock(mutex);
        shown=SnapshotDesktopPresentation(presentation,sample_owner);
        shown["elapsedMs"] = Elapsed(); shown["playing"]=true;
        shown["viewportWidth"] = width; shown["viewportHeight"] = height;
        step = requested_step; index = action_index; png=requested_step_png; expected_document=requested_step_document; ticket=requested_ticket;
        purpose=requested_purpose; terminal_identity=requested_terminal_identity;
      }
      if(step>=0 && !expected_document.empty() && expected_document!=before.tab.document_version)
        throw std::runtime_error("CAPTURE_TARGET_DOCUMENT_CHANGED");
      shown["tabId"]=lease.id; shown["generation"]=lease.generation;
      shown["documentVersion"]=before.tab.document_version;
      shown["visualViewport"]=viewport.at("visualViewport");
      const double frame_time=Elapsed(); shown["elapsedMs"]=frame_time;
      const auto timing_pre=stage_timing.Now();
      BrowserScreenshot image;
      result = engine.Screenshot(lease, &image, std::chrono::seconds(3));
      const auto timing_screenshot=stage_timing.Now();
      if (!result.ok) throw std::runtime_error("CAPTURE_FRAME_FAILED");
      result = engine.GetNavigationState(lease, &after, std::chrono::seconds(2));
      const auto timing_post_nav=stage_timing.Now();
      if (!result.ok) throw std::runtime_error("CAPTURE_DOCUMENT_UNAVAILABLE");
      if (before.tab.document_version != after.tab.document_version) {
#if defined(KELPIE_TEST_G08_ROI_WITNESS)
        test_scope_intact = false;
#endif
        bool cleared=false;
        { std::lock_guard lock(mutex); cleared=ClearRetiredDesktopPresentation(presentation,sample_owner); }
        ++dropped;
        if(cleared) Present();
        continue;
      }
      Json after_viewport;
      result = engine.EvaluateBrowserControl(lease, viewport_expression, &after_viewport, std::chrono::seconds(2));
      if (!result.ok || after_viewport != viewport) {
        ViewportDiagnostic(result.ok ? "before-after" : "after-read-failed",viewport,after_viewport);
        throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
      }
      const auto timing_post=stage_timing.Now();
#if defined(KELPIE_TEST_G08_ROI_WITNESS)
      // The listener is checked before first admission and at final disposition;
      // the hosted parent must separately prove it held that listener throughout.
      if (!test_scope_started) {
        test_scope_started = true;
        test_scope_document = before.tab.document_version;
        test_scope_viewport = viewport;
        test_scope_intact = test_scope.MatchesUrl(before.tab.url) && test_scope.ListenerOwned() &&
          width == 1042 && height == 662;
      }
      bool test_grant_current = false;
      try { test_grant_current = config.revalidate && config.revalidate(owner); } catch (...) {}
      test_scope_intact = test_scope_intact && test_scope.MatchesUrl(before.tab.url) &&
        test_scope.MatchesUrl(after.tab.url) && !test_scope_document.empty() &&
        before.tab.id == lease.id && after.tab.id == lease.id &&
        before.tab.generation == lease.generation && after.tab.generation == lease.generation &&
        before.tab.document_version == test_scope_document && after.tab.document_version == test_scope_document &&
        viewport == test_scope_viewport && after_viewport == test_scope_viewport &&
        test_grant_current && !abort->load();
      // Override rather than inherit anything with this name from presentation.
      shown["_testG08Scope"] = test_scope_intact;
#endif
      const bool terminal=step>=0 && purpose==DesktopScriptFramePurpose::TerminalClear && encoder->SupportsTerminalClear();
      if (terminal) {
        if (!config.revalidate || !config.revalidate(owner)) {
          grant_revoked.store(true); abort->store(true); throw std::runtime_error("CAPTURE_AUTHORIZATION_REVOKED");
        }
        std::lock_guard lock(mutex);
        if (abort->load() || requested_ticket!=ticket || terminal_identity.is_null() ||
            DesktopTerminalMarkerIdentity(presentation)!=terminal_identity ||
            DesktopTerminalMarkerIdentity(shown)!=terminal_identity)
          throw std::runtime_error("CAPTURE_TERMINAL_FRAME_UNAVAILABLE");
      }
      const auto admitted=encoder->AddFrame(image, shown, frame_time, step >= 0 ? step : index, step >= 0 && png,
          terminal ? purpose : DesktopScriptFramePurpose::Ordinary);
      stage_timing.Add(frame_time,timing_start,timing_pre_nav,timing_pre,timing_screenshot,timing_post_nav,timing_post,stage_timing.Now());
      if (terminal && (!config.revalidate || !config.revalidate(owner))) {
        grant_revoked.store(true); abort->store(true); throw std::runtime_error("CAPTURE_AUTHORIZATION_REVOKED");
      }
      const bool proof=!movies || expected_document.empty() ||
        (admitted.committed_marker_action==step && admitted.committed_marker_document==expected_document);
      Present();
      { std::lock_guard lock(mutex); if(!sampler_ready) { sampler_ready=true; changed.notify_all(); } }
      if (step >= 0) {
        std::lock_guard lock(mutex);
        if (terminal && (abort->load() || requested_ticket!=ticket ||
            DesktopTerminalMarkerIdentity(presentation)!=terminal_identity))
          throw std::runtime_error("CAPTURE_TERMINAL_FRAME_UNAVAILABLE");
        if(requested_ticket==ticket) requested_step_png=false; // Exclusive PNG path is written once.
        if(proof) {
          completed_step = step; completed_ticket=std::max(completed_ticket,ticket);
          if (requested_ticket == ticket) requested_step = -1;
        }
        changed.notify_all();
      }
      if (terminal) break;
      // An early milestone request does not consume a future cadence slot.
      if(acquisition>=next) next += interval;
      const auto now=Clock::now();
      if(next<now) {
        const auto skipped=static_cast<std::size_t>((now-next)/interval)+1;
        dropped+=skipped; next+=interval*skipped;
      }
      std::unique_lock lock(mutex);
      const auto capture_deadline=began+std::chrono::milliseconds(duration);
      changed.wait_until(lock, std::min(next,capture_deadline), [this,ticket] {
        return (requested_step>=0 && requested_ticket!=ticket) || stop_sampler.load() || abort->load();
      });
    }
  } catch (const std::exception& error) {
    // Only fixed native codes cross this boundary. Never return codec exception text or page data.
    const std::string value = error.what();
    reason = value.rfind("CAPTURE_", 0) == 0 && value.size() < 80 ? value : "CAPTURE_FAILED";
    { std::lock_guard lock(mutex); if(!abort->load()) capture_error = reason; }
    partial = true;
  } catch (...) {
    reason = "CAPTURE_FAILED";
    { std::lock_guard lock(mutex); if(!abort->load()) capture_error = reason; }
    partial = true;
  }
  try { Present(); } catch(...) { std::lock_guard lock(mutex); capture_error="CAPTURE_NATIVE_PRESENTATION_FAILED"; partial=true; }
  partial = partial || abort->load();
  if (encoder) {
    try {
      Json finalized = encoder->Finish(partial, reason, Elapsed());
#if defined(KELPIE_TEST_G08_ROI_WITNESS)
      // The private rows never enter public status or artifact JSON.
      Json test_rows=finalized.value("_testG08WitnessRows",Json());
      finalized.erase("_testG08WitnessRows");
      if(test_scope_started && test_scope_intact && !partial && !abort->load() &&
          !finalized.contains("error") && test_rows.is_array() && !test_rows.empty() && test_rows.size()<=800) {
        BrowserNavigationState final_navigation;
        Json final_viewport;
        const auto final_nav=engine.GetNavigationState(lease,&final_navigation,std::chrono::seconds(2));
        const auto final_view=engine.EvaluateBrowserControl(lease,viewport_expression,&final_viewport,std::chrono::seconds(2));
        bool final_grant=false;
        try { final_grant=config.revalidate && config.revalidate(owner); } catch (...) {}
        if(final_nav.ok && final_view.ok && final_grant && !abort->load() &&
            final_navigation.tab.id==lease.id && final_navigation.tab.generation==lease.generation &&
            final_navigation.tab.document_version==test_scope_document &&
            test_scope.MatchesUrl(final_navigation.tab.url) && final_viewport==test_scope_viewport &&
            test_scope.ListenerOwned()) {
          for(const auto& row:test_rows) {
            const auto hash=row.value("roiSha256",std::string());
            if(hash.size()!=64) { test_scope_intact=false; break; }
            if(std::fprintf(stderr,"KELPIE_TEST_G08_ROI_ROW %zu %lld %s\n",row.value("frameIndex",std::size_t{}),
              static_cast<long long>(row.value("pts100ns",std::int64_t{})),hash.c_str())<0) { test_scope_intact=false; break; }
          }
          bool disposition_grant=false;
          try { disposition_grant=config.revalidate && config.revalidate(owner); } catch (...) {}
          if(test_scope_intact && disposition_grant && !abort->load() && test_scope.ListenerOwned() && std::fflush(stderr)==0)
            std::fprintf(stderr,"KELPIE_TEST_G08_ROI_DONE %zu\n",test_rows.size());
        }
      }
#endif
      Json completed=finalized.value("artifacts",Json::array());
      if(finalized.contains("error")) { std::lock_guard lock(mutex); capture_error=finalized["error"]; }
      std::lock_guard lock(mutex);
      for (auto& artifact : completed) {
        artifact["viewport"] = {{"width", initial_width}, {"height", initial_height}};
        if (!first_document.empty() && !artifact.contains("documentId")) artifact["documentId"] = first_document;
        artifact["droppedFrames"] = artifact.value("droppedFrames", 0) + dropped;
      }
      artifacts = std::move(completed);
    } catch (...) { std::lock_guard lock(mutex); capture_error = "CAPTURE_FINALIZE_FAILED"; }
  }
  { std::lock_guard lock(mutex); sampler_done = true; changed.notify_all(); }
}
}
