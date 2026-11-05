#include "script_capture_service.h"
#include "kelpie/desktop_presentation_order.h"
#include "script_capture_cadence.h"
#include "kelpie/script_presentation.h"
#include "script_media_encoder.h"
#include "script_frame_compositor.h"
#include "script_native_overlay.h"
#include <set>
#include <deque>
#include <algorithm>

namespace kelpie::windows {
namespace {
class Capture final : public DesktopScriptCapture {
 public:
  Capture(std::shared_ptr<WindowsScriptService> service,const Json& options,std::string run,std::string owner)
      : service_(std::move(service)),options_(options),run_(std::move(run)),owner_(std::move(owner)) {
    directory_=CreatePrivateCaptureDirectory(run_);
    std::vector<std::string> codecs;
    for(const auto& format:options_.at("formats")) {
      const auto name=format.get<std::string>();
      if(name=="screenshots") screenshots_=true; else codecs.push_back(name=="video"?"mp4":name);
    }
    movies_=!codecs.empty();
    try { encoder_=ScriptMediaEncoder::Create(directory_,codecs,options_.value("fps",15),options_.value("maxBytes",std::size_t(67108864))); }
    catch(...) { std::error_code ignored; std::filesystem::remove(directory_,ignored); throw; }
  }
  ~Capture() override {
    std::error_code ignored;
    encoder_.reset();
    for(const auto& entry:owned_) if(!retained_.contains(entry.first))
      RemoveCaptureFile(entry.first,entry.second);
    std::filesystem::remove(directory_,ignored);
  }
  DesktopScriptFrameAdmission AddFrame(const BrowserScreenshot& image,const Json& presentation,double elapsed_ms,int index,bool step) override {
    ScriptFrameSourceSize source;
    auto frame=DecodeScriptFrame(image.base64_data,options_.value("maxWidth",1280),elapsed_ms,&source);
    if(source_width_ && (source.width!=source_width_ || source.height!=source_height_)) throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
    source_width_=source.width; source_height_=source.height;
    if(width_&& (frame.width!=width_||frame.height!=height_)) throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
    width_=frame.width; height_=frame.height; last_elapsed_=elapsed_ms;
    DrawScriptOverlay(frame,presentation);
    DesktopScriptFrameAdmission committed;
    if(ScriptMovieFrameDue(last_movie_frame_,elapsed_ms,options_.value("fps",15))) {
      // AddFrame emits the prior pending frame to GIF and MP4 before accepting
      // this new pending frame. False/throw never acknowledges either format.
      if(!encoder_->AddFrame(frame)) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
      DesktopScriptFrameAdmission queued;
      if(movies_ && presentation.contains("marker")) {
        const auto& marker=presentation.at("marker");
        const auto progress=kelpie_script_progress(elapsed_ms-marker.value("startedMs",0.0),marker.value("durationMs",700.0));
        if(kelpie_script_tap_presentation(progress,marker.value("wobble",true),marker.value("fade",true)).alpha>0) {
          queued.committed_marker_action=marker.value("actionIndex",-1);
          queued.committed_marker_document=presentation.value("documentVersion",std::string());
        }
      }
      if(movies_) {
        movie_markers_.push_back(std::move(queued));
        // Runtime cadence is <=30 FPS, so every GIF source interval is above
        // its 10ms minimum; H.264 baseline output is FIFO. Count only samples
        // actually retained by BOTH writers, never raw/MFT input acceptance.
        const auto prefix=encoder_->committed_movie_frames();
        while(committed_marker_frames_<prefix && !movie_markers_.empty()) {
          committed=std::move(movie_markers_.front()); movie_markers_.pop_front();
          ++committed_marker_frames_;
        }
        if(movie_markers_.size()>18) throw std::runtime_error("CAPTURE_ENCODER_BACKPRESSURE");
      }
      last_movie_frame_=elapsed_ms;
    }
    if(step&&screenshots_) {
      const auto path=directory_/("step-"+std::to_string(index)+".png");
      if(!encoder_->WriteStepPNG(frame,path)) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
      owned_[path]=CaptureFileIdentity(path);
      manifests_.push_back(service_->Publish(path,"image/png",{{"width",frame.width},{"height",frame.height},{"actionIndex",index},{"documentId",presentation.value("documentVersion",std::string())}},run_,owner_));
      retained_.insert(path);
    }
    return committed;
  }
  Json Finish(bool partial,const std::string&,double terminal_elapsed_ms) override {
    std::string failure;
    std::vector<ScriptMediaOutput> outputs;
    try { outputs=encoder_->Finish(std::max(last_elapsed_+1,terminal_elapsed_ms)); }
    catch(...) { failure="CAPTURE_FINALIZE_FAILED"; try { outputs=encoder_->Finish(std::max(last_elapsed_+1,terminal_elapsed_ms)); } catch(...) {} }
    try {
      for(const auto& output:outputs) owned_[output.path]=CaptureFileIdentity(output.path);
      for(const auto& output:outputs) {
        Json metadata={{"width",output.width},{"height",output.height},{"durationMs",output.duration_ms},
          {"frameCount",output.frame_count},{"droppedFrames",output.dropped_frames},{"partial",partial}};
        manifests_.push_back(service_->Publish(output.path,output.mime_type,metadata,run_,owner_));
        retained_.insert(output.path);
      }
      if(encoder_->budget_exceeded()) failure="CAPTURE_BUDGET_EXCEEDED";
    } catch(...) { failure="CAPTURE_FINALIZE_FAILED"; }
    Json result={{"artifacts",manifests_}};
    if(!failure.empty()) result["error"]=failure;
    return result;
  }
 private:
  std::shared_ptr<WindowsScriptService> service_;
  Json options_,manifests_=Json::array();
  std::string run_,owner_;
  std::filesystem::path directory_;
  std::unique_ptr<ScriptMediaEncoder> encoder_;
  std::set<std::filesystem::path> retained_;
  std::map<std::filesystem::path,BY_HANDLE_FILE_INFORMATION> owned_;
  bool screenshots_=false,movies_=false;
  std::deque<DesktopScriptFrameAdmission> movie_markers_;
  std::size_t committed_marker_frames_=0;
  int width_=0,height_=0,source_width_=0,source_height_=0;
  double last_elapsed_=0,last_movie_frame_=-1;
};
}
void WindowsScriptService::Configure(DesktopApp::Config& config) {
  auto self=shared_from_this();
  config.scripts.capture=[self](const Json& options,const std::string& run,const std::string& owner) {
    {std::lock_guard lock(self->mutex_);self->Expire();}
    return std::make_unique<Capture>(self,options,run,owner);
  };
  config.scripts.discard=[self](const std::string& run,const std::string& owner) { self->Discard(run,owner); };
  config.scripts.artifact=[self](const Json& body,const std::string& owner) { return self->Read(body,owner); };
  config.scripts.present=[self](const Json& presentation,std::function<void()> stop,std::function<bool()> valid) { self->Show(presentation,std::move(stop),std::move(valid)); };
}
void WindowsScriptService::Show(const Json& presentation,std::function<void()> stop,std::function<bool()> valid) {
  auto self=shared_from_this();
  if(!marshal_([self,presentation,stop=std::move(stop),valid=std::move(valid)]() mutable {
    try {
    if(!AcceptDesktopPresentationRevision(presentation,self->last_presentation_revision_)) return true;
    if(!self->overlay_) self->overlay_=std::make_unique<ScriptNativeOverlay>(self->viewport_,self->owner_,self->guard_);
    auto shown=presentation;
    if(!shown.value("detachedMarker",false) && self->guard_ && !self->guard_(shown)) {
      shown.erase("marker"); shown.erase("pointer"); shown.erase("commentary");
    }
    self->overlay_->Show(shown,std::move(stop),std::move(valid)); return true;
    } catch(...) {
      if(self->overlay_ && presentation.value("detachedMarker",false))
        self->overlay_->RetireIfRevision(presentation.value("_presentationRevision",std::uint64_t{}));
      return false;
    }
  })) throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
}
}
