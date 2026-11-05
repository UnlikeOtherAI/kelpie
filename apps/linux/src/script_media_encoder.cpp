#include "script_media_internal.h"
#include "script_artifact_store.h"
#include <algorithm>
#include <cmath>
#include <optional>
#include <limits>
#include <set>
#include <stdexcept>

namespace kelpie::linuxapp {
struct ScriptMediaEncoder::Impl {
  media::Budget budget;
  std::vector<std::unique_ptr<media::Writer>> writers;
  std::vector<ScriptMediaOutput> outputs;
  std::optional<ScriptFrame> pending;
  std::set<std::filesystem::path> pngs;
  double first = 0, last = 0;
  int width = 0, height = 0, fps;
  bool finished = false, stopped = false, failed = false;
  bool terminal_clear = false;
  explicit Impl(std::size_t max_bytes, int frame_rate) : budget{max_bytes}, fps(frame_rate) {}
  bool Emit(double terminal, ScriptMediaFramePurpose purpose = ScriptMediaFramePurpose::Ordinary) {
    bool accepted = true;
    for (auto& writer : writers) if (!writer->Write(*pending, pending->elapsed_ms - first, terminal - first, purpose)) accepted = false;
    return accepted;
  }
};
ScriptMediaEncoder::ScriptMediaEncoder(std::unique_ptr<Impl> impl) : impl_(std::move(impl)) {}
ScriptMediaEncoder::~ScriptMediaEncoder() = default;
std::unique_ptr<ScriptMediaEncoder> ScriptMediaEncoder::Create(const std::filesystem::path& directory,
    const std::vector<std::string>& formats, int fps, std::size_t max_bytes) {
  if (fps < 1 || fps > 60 || max_bytes < 1024 || max_bytes > 268435456 || formats.size() > 2)
    throw std::runtime_error("CAPTURE_OPTIONS_INVALID");
  std::set<std::string> unique;
  auto impl = std::make_unique<Impl>(max_bytes, fps);
  for (const auto& format : formats) {
    if (!unique.insert(format).second) throw std::runtime_error("CAPTURE_OPTIONS_INVALID");
    if (format == "gif") impl->writers.push_back(media::MakeGif(directory / "capture.gif", impl->budget));
    else if (format == "mp4") impl->writers.push_back(media::MakeVideo(directory / "capture.mp4", impl->budget, fps));
    else throw std::runtime_error("CAPTURE_OPTIONS_INVALID");
  }
  return std::unique_ptr<ScriptMediaEncoder>(new ScriptMediaEncoder(std::move(impl)));
}
bool ScriptMediaEncoder::AddFrame(const ScriptFrame& frame) {
  auto& state = *impl_;
  if (state.finished || state.stopped) throw std::runtime_error("CAPTURE_ALREADY_FINISHED");
  if (!std::isfinite(frame.elapsed_ms) || frame.elapsed_ms < 0 || frame.elapsed_ms > 3600000 || frame.width < 2 || frame.height < 2 ||
      frame.width > 4096 || frame.height > 4096 || frame.width % 2 || frame.height % 2 ||
      std::uint64_t(frame.width) * frame.height > 8388608 || frame.stride != frame.width * 4 ||
      frame.bgra.size() != std::size_t(frame.stride) * frame.height)
    throw std::runtime_error("CAPTURE_FRAME_INVALID");
  if (!state.pending) {
    for (auto& writer : state.writers) writer->Prepare(frame);
    state.first = frame.elapsed_ms; state.width = frame.width; state.height = frame.height;
  } else {
    if (frame.elapsed_ms <= state.last) throw std::runtime_error("CAPTURE_TIMESTAMP_INVALID");
    if (frame.width != state.width || frame.height != state.height) throw std::runtime_error("CAPTURE_VIEWPORT_CHANGED");
    if (!state.Emit(frame.elapsed_ms)) { state.pending.reset(); state.stopped = true; return false; }
  }
  state.last = frame.elapsed_ms; state.pending = frame; state.terminal_clear=false; return true;
}
bool ScriptMediaEncoder::MarkTerminalClear(const ScriptFrame& observed) {
  auto& state=*impl_;
  if (state.finished || state.stopped || !state.pending) return false;
  const auto& pending=*state.pending;
  if (pending.width!=observed.width || pending.height!=observed.height ||
      pending.stride!=observed.stride || pending.bgra!=observed.bgra) return false;
  state.terminal_clear=true; return true;
}
void ScriptMediaEncoder::ClearTerminalClear() { impl_->terminal_clear=false; }
bool ScriptMediaEncoder::WriteStepPNG(const ScriptFrame& frame, const std::filesystem::path& path) {
  auto& state = *impl_;
  if (state.finished || state.stopped) throw std::runtime_error("CAPTURE_ALREADY_FINISHED");
  if (state.pngs.contains(path)) throw std::runtime_error("CAPTURE_OUTPUT_EXISTS");
  auto bytes = EncodeScriptPNG(frame);
  if (!state.budget.Take(bytes.size())) { state.stopped = true; return false; }
  try { WriteCaptureFile(path, bytes); state.pngs.insert(path); }
  catch (...) { state.budget.Release(bytes.size()); throw; }
  return true;
}
std::vector<ScriptMediaOutput> ScriptMediaEncoder::Finish(double terminal_elapsed_ms) {
  auto& state = *impl_;
  if (state.finished) return state.outputs;
  if (!std::isfinite(terminal_elapsed_ms) || terminal_elapsed_ms > 3600000 || (state.pending && terminal_elapsed_ms <= state.last))
    throw std::runtime_error("CAPTURE_TIMESTAMP_INVALID");
  if (state.pending) {
    state.Emit(terminal_elapsed_ms, state.terminal_clear ? ScriptMediaFramePurpose::TerminalClear : ScriptMediaFramePurpose::Ordinary);
    state.pending.reset();
  }
  for (auto& writer : state.writers) {
    try {
      auto output = writer->Finish();
      if (output.frame_count) state.outputs.push_back(std::move(output));
      else state.failed = true; // A requested movie format cannot silently be empty.
    } catch (...) { state.failed = true; }
  }
  state.finished = true; return state.outputs;
}
std::size_t ScriptMediaEncoder::committed_movie_frames() const {
  if (impl_->writers.empty()) return 0;
  auto prefix = std::numeric_limits<std::size_t>::max();
  for (const auto& writer : impl_->writers) prefix = std::min(prefix, writer->CommittedSourceFrames());
  return prefix;
}
bool ScriptMediaEncoder::budget_exceeded() const { return impl_->budget.exceeded; }
bool ScriptMediaEncoder::finalization_failed() const { return impl_->failed; }
}
