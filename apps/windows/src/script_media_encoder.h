#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace kelpie::windows {

struct ScriptMediaFrame {
  int width = 0;
  int height = 0;
  int stride = 0;  // Zero means width * 4. BGRA8, top-down, opaque composited pixels.
  std::vector<std::uint8_t> bgra;
  double elapsed_ms = 0;
};

struct ScriptMediaOutput {
  std::filesystem::path path;
  std::string mime_type;
  int width = 0;
  int height = 0;
  double duration_ms = 0;
  std::size_t frame_count = 0;
  std::size_t dropped_frames = 0;
};

// Own on one worker thread, including destruction. The encoder initializes COM
// and Media Foundation there. Stop sampling before Finish; never abandon it on
// cancellation. No page content or output path appears in exception messages.
class ScriptMediaEncoder {
 public:
  // Formats: "gif", "mp4"; empty allows PNG-only callers. fps: 1..60.
  // Total GIF+MP4+WriteStepPNG budget: 1..256 MiB, including finalization headroom.
  // Frames: at most 4096 per dimension and 8,388,608 pixels; MP4 needs even
  // dimensions. Raw buffers are bounded independently from the output budget.
  static std::unique_ptr<ScriptMediaEncoder> Create(
      const std::filesystem::path& directory,
      const std::vector<std::string>& formats,
      int fps,
      std::size_t max_bytes = 64 * 1024 * 1024);
  ~ScriptMediaEncoder();

  ScriptMediaEncoder(const ScriptMediaEncoder&) = delete;
  ScriptMediaEncoder& operator=(const ScriptMediaEncoder&) = delete;

  // Strictly increasing, finite timestamps, with first frame normalized to t=0.
  // Retains one pending raw frame to derive actual frame duration. False means
  // stop sampling and call Finish: previously admitted frames stay playable.
  bool AddFrame(const ScriptMediaFrame& frame);

  // terminal_elapsed_ms is in the caller's elapsed clock, not normalized time.
  // Final timestamp must exceed the last accepted frame. Repeat returns the
  // same manifest. Empty capture returns no files. GIF rounds cumulative frame
  // boundaries to centiseconds; MP4 preserves 100 ns timing.
  std::vector<ScriptMediaOutput> Finish(double terminal_elapsed_ms);

  // PNG helper uses WIC on this worker. The caller owns step-artifact budgeting.
  static void WritePNG(const ScriptMediaFrame& frame, const std::filesystem::path& path);

  // Exact PNG byte admission against the same retained-media budget. False
  // writes nothing. Service owns the PNG step manifest.
  bool WriteStepPNG(const ScriptMediaFrame& frame, const std::filesystem::path& path);

  std::size_t bytes_written() const;
  bool budget_exceeded() const;

 private:
  struct Impl;
  explicit ScriptMediaEncoder(std::unique_ptr<Impl> impl);
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie::windows