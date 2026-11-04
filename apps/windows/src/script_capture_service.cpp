#include "script_capture_service.h"
#include "script_capture_cadence.h"
#include "script_media_encoder.h"
#include "script_frame_compositor.h"
#include "script_native_overlay.h"
#include <set>
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
    try { encoder_=ScriptMediaEncoder::Create(directory_,codecs,options_.value("fps",15),options_.value("maxBytes",std::size_t(67108864))); }
    catch(...) { std::error_code ignored; std::filesystem::remove(directory_,ignored); throw; }
  }
  ~Capture() override {
    std::error_code ignored;
    for(const auto& entry:std::filesystem::directory_iterator(directory_,ignored)) if(!retained_.contains(entry.path()))
      std::filesystem::remove(entry.path(),ignored);
    std::filesystem::remove(directory_,ignored);
  }
  void AddFrame(const BrowserScreenshot& image,const Json& presentation,double elapsed_ms,int index,bool step) override {
    auto frame=DecodeScriptFrame(image.base64_data,options_.value("maxWidth",1280),elapsed_ms);
    if(width_&& (frame.width!=width_||frame.height!=height_)) throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
    width_=frame.width; height_=frame.height; last_elapsed_=elapsed_ms;
    DrawScriptOverlay(frame,presentation);
    if(ScriptMovieFrameDue(last_movie_frame_,elapsed_ms,options_.value("fps",15))) {
      if(!encoder_->AddFrame(frame)) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
      last_movie_frame_=elapsed_ms;
    }
    if(step&&screenshots_) {
      const auto path=directory_/("step-"+std::to_string(index)+".png");
      if(!encoder_->WriteStepPNG(frame,path)) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
      manifests_.push_back(service_->Publish(path,"image/png",{{"width",frame.width},{"height",frame.height},{"actionIndex",index},{"documentId",presentation.value("documentVersion",std::string())}},run_,owner_));
      retained_.insert(path);
    }
  }
  Json Finish(bool partial,const std::string&,double terminal_elapsed_ms) override {
    std::string failure;
    std::vector<ScriptMediaOutput> outputs;
    try { outputs=encoder_->Finish(std::max(last_elapsed_+1,terminal_elapsed_ms)); }
    catch(...) { failure="CAPTURE_FINALIZE_FAILED"; try { outputs=encoder_->Finish(std::max(last_elapsed_+1,terminal_elapsed_ms)); } catch(...) {} }
    try {
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
  bool screenshots_=false;
  int width_=0,height_=0;
  double last_elapsed_=0,last_movie_frame_=-1;
};
}
WindowsScriptService::WindowsScriptService(HWND viewport,HWND owner,Marshal marshal,DocumentGuard guard)
    :viewport_(viewport),owner_(owner),marshal_(std::move(marshal)),guard_(std::move(guard)) {}
WindowsScriptService::~WindowsScriptService() {
  overlay_.reset();
  for(const auto& [id,entry]:entries_) {
    std::error_code ignored; std::filesystem::remove(entry.path,ignored); std::filesystem::remove(entry.path.parent_path(),ignored);
  }
}
void WindowsScriptService::Configure(DesktopApp::Config& config) {
  auto self=shared_from_this();
  config.scripts.capture=[self](const Json& options,const std::string& run,const std::string& owner) {
    return std::make_unique<Capture>(self,options,run,owner);
  };
  config.scripts.artifact=[self](const Json& body,const std::string& owner) { return self->Read(body,owner); };
  config.scripts.present=[self](const Json& presentation,std::function<void()> stop) { self->Show(presentation,std::move(stop)); };
}
void WindowsScriptService::Show(const Json& presentation,std::function<void()> stop) {
  auto self=shared_from_this();
  if(!marshal_([self,presentation,stop=std::move(stop)]() mutable {
    try {
    if(!self->overlay_) self->overlay_=std::make_unique<ScriptNativeOverlay>(self->viewport_,self->owner_);
    auto shown=presentation;
    if(self->guard_ && !self->guard_(shown)) {
      shown.erase("marker"); shown.erase("pointer"); shown.erase("commentary"); shown["captureLatched"]=false;
    }
    self->overlay_->Show(shown,std::move(stop)); return true;
    } catch(...) { return false; }
  })) throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
}
}
