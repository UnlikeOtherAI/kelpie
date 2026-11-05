#pragma once
#include "script_media_encoder.h"
#include <cstddef>
#include <memory>

namespace kelpie::linuxapp::media {
struct Budget {
  std::size_t limit, used = 0;
  bool exceeded = false;
  bool Take(std::size_t bytes) {
    if (bytes > limit - used) { exceeded = true; return false; }
    used += bytes; return true;
  }
  void Release(std::size_t bytes) { used -= bytes; }
};
class Writer {
 public:
  virtual ~Writer() = default;
  virtual void Prepare(const ScriptFrame&) {}
  virtual bool Write(const ScriptFrame& frame, double start_ms, double end_ms, ScriptMediaFramePurpose purpose) = 0;
  virtual ScriptMediaOutput Finish() = 0;
  virtual std::size_t CommittedSourceFrames() const = 0;
};
std::unique_ptr<Writer> MakeGif(const std::filesystem::path& path, Budget& budget);
std::unique_ptr<Writer> MakeVideo(const std::filesystem::path& path, Budget& budget, int fps);
}
