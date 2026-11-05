#include "script_capture_service.h"
#include "script_frame_compositor.h"
#include "script_media_encoder.h"
#include "kelpie/script_presentation.h"
#include <deque>
#include <algorithm>
#include <set>
#include <map>
#include <stdexcept>

namespace kelpie::linuxapp {
namespace {
class Capture final : public DesktopScriptCapture {
 public:
  Capture(std::shared_ptr<LinuxScriptService> service, const Json& options, std::string run, std::string owner)
      : service_(std::move(service)), options_(options), run_(std::move(run)), owner_(std::move(owner)),
        directory_(CreatePrivateCaptureDirectory()) {
    try {
      std::vector<std::string> formats;
      for (const auto& value : options_.at("formats")) {
        const auto format = value.get<std::string>();
        if (format == "screenshots") screenshots_ = true; else formats.push_back(format == "video" ? "mp4" : format);
      }
      movies_ = !formats.empty();
      encoder_ = ScriptMediaEncoder::Create(directory_, formats, options_.value("fps", 15), options_.value("maxBytes", std::size_t(67108864)));
    }
    catch (...) { std::error_code ignored; std::filesystem::remove(directory_, ignored); throw; }
  }
  ~Capture() override {
    encoder_.reset();
    for (const auto& [path, identity] : owned_)
      if (!retained_.contains(path)) RemoveCaptureFile(path, identity);
    std::error_code ignored;
    std::filesystem::remove(directory_, ignored); // Preserve unrelated collision files.
  }
  DesktopScriptFrameAdmission AddFrame(const BrowserScreenshot& image, const Json& shown, double elapsed, int index, bool step) override {
    auto frame = DecodeScriptFrame(image.base64_data, options_.value("maxWidth", 1280), elapsed);
    if (width_ && (width_ != frame.width || height_ != frame.height)) throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
    width_ = frame.width; height_ = frame.height; last_elapsed_ = elapsed;
    DrawScriptOverlay(frame, shown);
    DesktopScriptFrameAdmission committed;
    // Step PNG requests share samples but must not increase movie frame rate.
    if (last_movie_frame_ < 0 || elapsed - last_movie_frame_ + .000001 >= 1000.0 / options_.value("fps", 15)) {
      if (!encoder_->AddFrame(frame)) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
      if (movies_) {
        DesktopScriptFrameAdmission queued;
        if (shown.contains("marker")) {
          const auto& marker = shown.at("marker");
          const double progress = kelpie_script_progress(elapsed - marker.value("startedMs", elapsed),
              marker.value("durationMs", 700.0));
          if (kelpie_script_tap_presentation(progress, marker.value("wobble", true), marker.value("fade", true)).alpha > 0) {
            queued.committed_marker_action = marker.value("actionIndex", -1);
            queued.committed_marker_document = shown.value("documentVersion", std::string());
          }
        }
        movie_markers_.push_back(std::move(queued));
        const auto prefix = encoder_->committed_movie_frames();
        while (committed_marker_frames_ < prefix && !movie_markers_.empty()) {
          committed = std::move(movie_markers_.front()); movie_markers_.pop_front();
          ++committed_marker_frames_;
        }
        if (movie_markers_.size() > 18) throw std::runtime_error("CAPTURE_ENCODER_BACKPRESSURE");
      }
      last_movie_frame_ = elapsed;
    }
    if (step && screenshots_) {
      const auto path = directory_ / ("step-" + std::to_string(index) + ".png");
      if (!encoder_->WriteStepPNG(frame, path)) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
      owned_.emplace(path, InspectCaptureFile(path));
      manifests_.push_back(service_->artifacts().Publish(path, "image/png",
          {{"width", frame.width}, {"height", frame.height}, {"actionIndex", index},
           {"documentId", shown.value("documentVersion", std::string())}}, run_, owner_));
      retained_.insert(path);
    }
    return committed;
  }
  Json Finish(bool partial, const std::string&, double terminal) override {
    if (finished_) return result_;
    std::string failure;
    std::vector<ScriptMediaOutput> outputs;
    try { outputs = encoder_->Finish(std::max(last_elapsed_ + 1, terminal)); }
    catch (...) { failure = "CAPTURE_FINALIZE_FAILED"; }
    for (const auto& output : outputs) {
      try {
        owned_.emplace(output.path, InspectCaptureFile(output.path));
        manifests_.push_back(service_->artifacts().Publish(output.path, output.mime_type,
            {{"width", output.width}, {"height", output.height}, {"durationMs", output.duration_ms},
             {"frameCount", output.frame_count}, {"droppedFrames", output.dropped_frames}, {"partial", partial}}, run_, owner_));
        retained_.insert(output.path);
      } catch (...) { failure = "CAPTURE_FINALIZE_FAILED"; }
    }
    if (encoder_->budget_exceeded()) failure = "CAPTURE_BUDGET_EXCEEDED";
    if (encoder_->finalization_failed()) failure = "CAPTURE_FINALIZE_FAILED";
    // Successful capture supplies every requested artifact family. Empty
    // encoder output or publication failure cannot become nominal success.
    if (failure.empty()) for (const auto& format : options_.at("formats")) {
      const auto name = format.get<std::string>();
      const std::string mime = name == "gif" ? "image/gif" : name == "video" ? "video/mp4" : "image/png";
      const bool present = std::any_of(manifests_.begin(), manifests_.end(),
          [&](const Json& item) { return item.value("mimeType", std::string()) == mime; });
      if (!present) { failure = "CAPTURE_FINALIZE_FAILED"; break; }
    }
    for (auto& item : manifests_) item["partial"] = partial || !failure.empty();
    result_ = {{"artifacts", manifests_}};
    if (!failure.empty()) result_["error"] = failure;
    finished_ = true; return result_;
  }
 private:
  std::shared_ptr<LinuxScriptService> service_;
  Json options_, manifests_ = Json::array(), result_;
  std::string run_, owner_;
  std::filesystem::path directory_;
  std::unique_ptr<ScriptMediaEncoder> encoder_;
  std::set<std::filesystem::path> retained_;
  std::map<std::filesystem::path, CaptureFileIdentity> owned_;
  int width_ = 0, height_ = 0;
  double last_elapsed_ = 0, last_movie_frame_ = -1;
  std::deque<DesktopScriptFrameAdmission> movie_markers_;
  std::size_t committed_marker_frames_ = 0;
  bool screenshots_ = false, movies_ = false, finished_ = false;
};
}
LinuxScriptService::LinuxScriptService(DocumentGuard guard) : guard_(std::move(guard)) {}
void LinuxScriptService::Configure(DesktopApp::Config& config) {
  auto self = shared_from_this();
  config.scripts.capture = [self](const Json& options, const std::string& run, const std::string& owner) {
    return std::make_unique<Capture>(self, options, run, owner);
  };
  config.scripts.discard = [self](const std::string& run, const std::string& owner) { self->artifacts_.Discard(run, owner); };
  config.scripts.artifact = [self](const Json& request, const std::string& owner) { return self->artifacts_.Read(request, owner); };
  config.scripts.present = [self](const Json& presentation, std::function<void()> stop) { self->Show(presentation, std::move(stop)); };
}
void LinuxScriptService::Show(const Json& presentation, std::function<void()> stop) {
  std::lock_guard lock(mutex_); presentation_ = presentation; stop_ = std::move(stop);
  shown_at_ = std::chrono::steady_clock::now();
}
LinuxScriptService::Json LinuxScriptService::Presentation() const {
  Json shown;
  {
    std::lock_guard lock(mutex_); shown = presentation_;
    if (shown.value("playing", false) && !shown.value("captureLatched", false))
      shown["elapsedMs"] = shown.value("elapsedMs", 0.0) +
          std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - shown_at_).count();
  }
  if (shown.value("playing", false) && guard_ && !guard_(shown)) { shown.erase("marker"); shown.erase("pointer"); shown.erase("commentary"); }
  return shown;
}
void LinuxScriptService::Stop() {
  std::function<void()> stop;
  { std::lock_guard lock(mutex_); stop = stop_; }
  if (stop) stop();
}
}
