#include "script_media_internal.h"

#include <mfapi.h>
#include <wincodec.h>
#include <algorithm>
#include <cmath>
#include <optional>
#include <set>
#include <thread>

namespace kelpie::windows {
namespace media {
int Stride(const ScriptMediaFrame& frame) {
  return frame.stride == 0 ? frame.width * 4 : frame.stride;
}

void ValidateFrame(const ScriptMediaFrame& frame) {
  if (frame.width <= 0 || frame.height <= 0 || frame.width > 4096 ||
      frame.height > 4096 ||
      static_cast<std::size_t>(frame.width) * frame.height > 8388608 ||
      Stride(frame) < frame.width * 4 || Stride(frame) > 4096 * 4 ||
      frame.bgra.size() != static_cast<std::size_t>(Stride(frame)) * frame.height ||
      !std::isfinite(frame.elapsed_ms) || frame.elapsed_ms < 0 ||
      frame.elapsed_ms > 3600000) {
    throw std::runtime_error("CAPTURE_INVALID_FRAME");
  }
}
}  // namespace media

struct ScriptMediaEncoder::Impl {
  std::thread::id owner = std::this_thread::get_id();
  media::Budget budget;
  std::filesystem::path directory;
  std::set<std::string> formats;
  int fps;
  bool com_started = false;
  bool mf_started = false;
  bool finished = false;
  double origin_ms = 0;
  double last_ms = 0;
  int width = 0;
  int height = 0;
  std::optional<ScriptMediaFrame> pending;
  std::unique_ptr<media::GifWriter> gif;
  std::unique_ptr<media::VideoWriter> video;
  std::vector<ScriptMediaOutput> outputs;
  std::vector<std::filesystem::path> pngs;

  Impl(const std::filesystem::path& dir, const std::vector<std::string>& requested,
       int rate, std::size_t max_bytes)
      : budget{max_bytes}, directory(dir), formats(requested.begin(), requested.end()), fps(rate) {
    if (fps < 1 || fps > 60 || max_bytes < 1024 * 1024 ||
        max_bytes > 256ULL * 1024 * 1024 ||
        formats.size() != requested.size() ||
        std::any_of(formats.begin(), formats.end(),
                    [](const auto& value) { return value != "gif" && value != "mp4"; })) {
      throw std::runtime_error("CAPTURE_INVALID_OPTIONS");
    }
    if (!std::filesystem::is_directory(directory))
      throw std::runtime_error("CAPTURE_DIRECTORY_UNAVAILABLE");
    // Never silently overwrite another capture, including a partly written run.
    for (const auto& format : formats) {
      if (std::filesystem::exists(directory / ("capture." + format)))
        throw std::runtime_error("CAPTURE_OUTPUT_EXISTS");
    }
    media::Check(CoInitializeEx(nullptr, COINIT_MULTITHREADED), "CAPTURE_COM_UNAVAILABLE");
    com_started = true;
    if (formats.count("mp4")) {
      const auto result = MFStartup(MF_VERSION, MFSTARTUP_LITE);
      if (FAILED(result)) {
        CoUninitialize();
        com_started = false;
        throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
      }
      mf_started = true;
    }
  }

  ~Impl() {
    // The owner guarantees destruction on the same worker as construction.
    video.reset();
    gif.reset();
    if (mf_started) MFShutdown();
    if (com_started) CoUninitialize();
  }

  void CheckOwner() const {
    if (owner != std::this_thread::get_id())
      throw std::runtime_error("CAPTURE_WRONG_THREAD");
  }

  bool Emit(double end_ms) {
    auto frame = std::move(*pending);
    pending.reset();
    const auto start_ms = frame.elapsed_ms - origin_ms;
    bool accepted = true;
    if (gif) accepted = gif->Write(frame, start_ms, end_ms - origin_ms);
    if (video && accepted) accepted = video->Write(frame, start_ms, end_ms - origin_ms);
    pending.reset();
    return accepted;
  }
};

ScriptMediaEncoder::ScriptMediaEncoder(std::unique_ptr<Impl> impl) : impl_(std::move(impl)) {}
ScriptMediaEncoder::~ScriptMediaEncoder() = default;

std::unique_ptr<ScriptMediaEncoder> ScriptMediaEncoder::Create(
    const std::filesystem::path& directory, const std::vector<std::string>& formats,
    int fps, std::size_t max_bytes) {
  return std::unique_ptr<ScriptMediaEncoder>(
      new ScriptMediaEncoder(std::make_unique<Impl>(directory, formats, fps, max_bytes)));
}

bool ScriptMediaEncoder::AddFrame(const ScriptMediaFrame& frame) {
  auto& state = *impl_;
  state.CheckOwner();
  if (state.finished) throw std::runtime_error("CAPTURE_ALREADY_FINISHED");
  if (state.budget.exceeded) return false;
  media::ValidateFrame(frame);
  if (state.width != 0) {
    if (frame.width != state.width || frame.height != state.height ||
        frame.elapsed_ms <= state.last_ms)
      throw std::runtime_error("CAPTURE_INVALID_FRAME");
    if (!state.Emit(frame.elapsed_ms)) return false;
  } else {
    if (state.formats.count("mp4") && ((frame.width & 1) || (frame.height & 1)))
      throw std::runtime_error("CAPTURE_VIDEO_REQUIRES_EVEN_SIZE");
    auto gif = state.formats.count("gif")
        ? media::CreateGif(state.directory / "capture.gif", state.budget) : nullptr;
    auto video = state.formats.count("mp4")
        ? media::CreateVideo(state.directory / "capture.mp4",
                            frame.width, frame.height, state.fps, state.budget) : nullptr;
    state.gif = std::move(gif);
    state.video = std::move(video);
    state.width = frame.width;
    state.height = frame.height;
    state.origin_ms = frame.elapsed_ms;
  }
  state.last_ms = frame.elapsed_ms;
  state.pending = frame;
  return true;
}

std::vector<ScriptMediaOutput> ScriptMediaEncoder::Finish(double terminal_elapsed_ms) {
  auto& state = *impl_;
  state.CheckOwner();
  if (state.finished) return state.outputs;
  if (!std::isfinite(terminal_elapsed_ms) ||
      (state.pending && terminal_elapsed_ms <= state.last_ms) ||
      terminal_elapsed_ms > 3600000 || terminal_elapsed_ms < 0)
    throw std::runtime_error("CAPTURE_INVALID_TIMESTAMP");

  // Finalize each format even if the other fails, preserving usable artifacts.
  std::exception_ptr failure;
  try { if (state.pending) state.Emit(terminal_elapsed_ms); }
  catch (...) { failure = std::current_exception(); }
  if (state.gif) {
    try {
      auto output = state.gif->Finish();
      if (output.frame_count) state.outputs.push_back(std::move(output));
    } catch (...) { failure = std::current_exception(); }
  }
  if (state.video) {
    try {
      auto output = state.video->Finish();
      if (output.frame_count) state.outputs.push_back(std::move(output));
    } catch (...) { if (!failure) failure = std::current_exception(); }
  }
  state.finished = true;
  if (failure) std::rethrow_exception(failure);
  return state.outputs;
}

std::size_t ScriptMediaEncoder::bytes_written() const {
  impl_->CheckOwner();
  std::size_t total = 0;
  for (const auto& format : impl_->formats) {
    std::error_code error;
    const auto bytes = std::filesystem::file_size(impl_->directory / ("capture." + format), error);
    if (!error) total += static_cast<std::size_t>(bytes);
  }
  for (const auto& path : impl_->pngs) {
    std::error_code error;
    const auto bytes = std::filesystem::file_size(path, error);
    if (!error) total += static_cast<std::size_t>(bytes);
  }
  return total;
}

bool ScriptMediaEncoder::budget_exceeded() const {
  impl_->CheckOwner();
  return impl_->budget.exceeded;
}

bool ScriptMediaEncoder::WriteStepPNG(
    const ScriptMediaFrame& frame, const std::filesystem::path& path) {
  impl_->CheckOwner();
  if (impl_->finished) throw std::runtime_error("CAPTURE_ALREADY_FINISHED");
  if (impl_->budget.exceeded) return false;
  if (path.extension() != ".png" ||
      path.parent_path().lexically_normal() != impl_->directory.lexically_normal())
    throw std::runtime_error("CAPTURE_INVALID_ARTIFACT_PATH");
  if (impl_->pngs.size() >= 4096) throw std::runtime_error("CAPTURE_STEP_LIMIT");
  const auto bytes = media::EncodePNG(frame);
  if (!impl_->budget.Take(bytes.size())) return false;
  media::WritePNGBytes(bytes, path);
  impl_->pngs.push_back(path);
  return true;
}

}  // namespace kelpie::windows