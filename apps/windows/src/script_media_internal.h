#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <wrl/client.h>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include "script_media_encoder.h"

namespace kelpie::windows::media {
using Microsoft::WRL::ComPtr;

inline void Check(HRESULT result, const char* code = "CAPTURE_ENCODING_FAILED") {
  if (FAILED(result)) throw std::runtime_error(code);
}

struct Budget {
  std::size_t limit;
  std::size_t reserved = 0;
  bool exceeded = false;
  bool Take(std::size_t count) {
    if (exceeded || count > limit - reserved) {
      exceeded = true;
      return false;
    }
    reserved += count;
    return true;
  }
};

void ValidateFrame(const ScriptMediaFrame& frame);
int Stride(const ScriptMediaFrame& frame);
std::vector<std::uint8_t> EncodePNG(const ScriptMediaFrame& frame);
void WritePNGBytes(const std::vector<std::uint8_t>&, const std::filesystem::path&);

class GifWriter {
 public:
  virtual ~GifWriter() = default;
  virtual bool Write(const ScriptMediaFrame&, double start_ms, double end_ms) = 0;
  virtual ScriptMediaOutput Finish() = 0;
};
class VideoWriter {
 public:
  virtual ~VideoWriter() = default;
  virtual bool Write(const ScriptMediaFrame&, double start_ms, double end_ms) = 0;
  virtual ScriptMediaOutput Finish() = 0;
};

std::unique_ptr<GifWriter> CreateGif(const std::filesystem::path&, Budget&);
std::unique_ptr<VideoWriter> CreateVideo(
    const std::filesystem::path&, int width, int height, int fps, Budget&);

}  // namespace kelpie::windows::media