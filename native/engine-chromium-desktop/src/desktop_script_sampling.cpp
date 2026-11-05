#include "desktop_script_runtime.h"
#include "desktop_script_coordinates.h"
#include "desktop_script_capture_state.h"
#include "desktop_capture_stage_timing.h"
#include "desktop_capture_receipt.h"
#ifdef KELPIE_CAPTURE_RECEIPT_TEST_HOOK
#include "desktop_capture_receipt_test_hook.h"
#endif
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
  std::unique_ptr<DesktopScriptCapture> encoder;
  int initial_width = 0, initial_height = 0;
  Json previous_viewport;
  std::string previous_document;
  const std::string viewport_expression="(()=>{const v=window.visualViewport;return {width:innerWidth,height:innerHeight,visualViewport:{offsetLeft:v?.offsetLeft??0,offsetTop:v?.offsetTop??0,width:v?.width??innerWidth,height:v?.height??innerHeight,scale:v?.scale??1}}})()";
  std::string first_document;
#ifdef KELPIE_CAPTURE_RECEIPT_TEST_HOOK
  std::optional<std::string> receipt_test_old_document;
  bool receipt_test_new_admitted=false;
#endif
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
      result = engine.CaptureScreenshot(lease, &image, &after, std::chrono::seconds(3));
#ifdef KELPIE_CAPTURE_RECEIPT_TEST_HOOK
      if(result.ok && !receipt_test_old_document && std::getenv("KELPIE_CAPTURE_RECEIPT_FIXTURE_URL")) {
        if(!config.revalidate || !config.revalidate(owner)) {
          grant_revoked.store(true);abort->store(true);
          throw std::runtime_error("CAPTURE_AUTHORIZATION_REVOKED");
        }
        receipt_test_old_document=ReceiptTestNavigateOnce(engine,lease,before);
      }
#endif
      const auto timing_screenshot=stage_timing.Now();
      const auto timing_post_nav=timing_screenshot;
      if (!result.ok) throw std::runtime_error(result.error_code=="CAPTURE_DOCUMENT_UNAVAILABLE" ?
          "CAPTURE_DOCUMENT_UNAVAILABLE" : "CAPTURE_FRAME_FAILED");
      if (before.tab.document_version != after.tab.document_version) {
        bool cleared=false;
        { std::lock_guard lock(mutex); cleared=ClearRetiredDesktopPresentation(presentation,sample_owner); }
        ++dropped;
        if(cleared) Present();
        continue;
      }
      Json after_viewport;
      auto after_lease=lease;
      after_lease.document_version=after.tab.document_version;
      result = engine.EvaluateBrowserControl(after_lease, viewport_expression, &after_viewport, std::chrono::seconds(2));
      if (!result.ok) {
        // A navigation after the receipt is a torn sample, just as it was
        // before the receipt optimization. Preserve the old drop/retry path.
        BrowserNavigationState latest;
        const auto observed=engine.GetNavigationState(lease,&latest,std::chrono::seconds(2));
        const auto failure=ClassifyCaptureViewportFailure(observed.ok,after.tab.document_version,latest.tab.document_version);
        if(failure==CaptureViewportFailure::DocumentUnavailable)
          throw std::runtime_error("CAPTURE_DOCUMENT_UNAVAILABLE");
        if(failure==CaptureViewportFailure::TornFrame) {
#ifdef KELPIE_CAPTURE_RECEIPT_TEST_HOOK
          if(receipt_test_old_document && before.tab.document_version==*receipt_test_old_document) {
            std::fputs("KELPIE_RECEIPT_TEST_TORN_DROPPED\n",stderr);std::fflush(stderr);
          }
#endif
          bool cleared=false;
          { std::lock_guard lock(mutex); cleared=ClearRetiredDesktopPresentation(presentation,sample_owner); }
          ++dropped;
          if(cleared) Present();
          continue;
        }
      }
      if (!result.ok || after_viewport != viewport) {
        ViewportDiagnostic(result.ok ? "before-after" : "after-read-failed",viewport,after_viewport);
        throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
      }
      const auto timing_post=stage_timing.Now();
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
#ifdef KELPIE_CAPTURE_RECEIPT_TEST_HOOK
      if(receipt_test_old_document) {
        if(shown.value("documentVersion",std::string())==*receipt_test_old_document)
          throw std::runtime_error("CAPTURE_RECEIPT_TEST_STALE_FRAME");

      }
#endif
      const auto admitted=encoder->AddFrame(image, shown, frame_time, step >= 0 ? step : index, step >= 0 && png,
          terminal ? purpose : DesktopScriptFramePurpose::Ordinary);
#ifdef KELPIE_CAPTURE_RECEIPT_TEST_HOOK
      if(receipt_test_old_document && !receipt_test_new_admitted) {
        std::fputs("KELPIE_RECEIPT_TEST_NEW_FRAME\n",stderr);std::fflush(stderr);
        receipt_test_new_admitted=true;
      }
#endif
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
