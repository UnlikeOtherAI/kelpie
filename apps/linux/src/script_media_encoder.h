#pragma once
#include "script_frame_compositor.h"
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace kelpie::linuxapp {
enum class ScriptMediaFramePurpose { Ordinary, TerminalClear };
struct ScriptMediaOutput {
  std::filesystem::path path;
  std::string mime_type;
  int width = 0, height = 0;
  double duration_ms = 0;
  std::size_t frame_count = 0, dropped_frames = 0;
};
class ScriptMediaEncoder {
 public:
  static std::unique_ptr<ScriptMediaEncoder> Create(const std::filesystem::path& directory,
      const std::vector<std::string>& formats, int fps, std::size_t max_bytes);
  ~ScriptMediaEncoder();
  bool AddFrame(const ScriptFrame& frame);
  bool MarkTerminalClear(const ScriptFrame& observed);
  bool WriteStepPNG(const ScriptFrame& frame, const std::filesystem::path& path);
  std::vector<ScriptMediaOutput> Finish(double terminal_elapsed_ms);
  // Minimum actual retained source prefix across every requested movie writer.
  std::size_t committed_movie_frames() const;
  bool budget_exceeded() const;
  bool finalization_failed() const;
 private:
  struct Impl;
  explicit ScriptMediaEncoder(std::unique_ptr<Impl> impl);
  std::unique_ptr<Impl> impl_;
};
}
