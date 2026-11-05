#include "script_media_internal.h"
#include "script_artifact_store.h"
#include <gif_lib.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <stdexcept>

namespace kelpie::linuxapp::media {
namespace {
struct Encoded { std::vector<std::uint8_t> bytes; std::size_t limit = 0; };
int WriteGif(GifFileType* file, const GifByteType* input, int count) {
  auto& output = *static_cast<Encoded*>(file->UserData);
  if (count < 0 || std::size_t(count) > output.limit - output.bytes.size()) return 0;
  try { output.bytes.insert(output.bytes.end(), input, input + count); return count; }
  catch (...) { return 0; }
}
std::vector<std::uint8_t> Encode(const ScriptFrame& frame) {
  Encoded output{{}, frame.bgra.size() * 2 + 4096}; int error = 0;
  std::unique_ptr<ColorMapObject, decltype(&GifFreeMapObject)> palette(GifMakeMapObject(256, nullptr), GifFreeMapObject);
  if (!palette) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  for (int i = 0; i < 256; ++i) palette->Colors[i] = {
      GifByteType(((i >> 5) & 7) * 255 / 7), GifByteType(((i >> 2) & 7) * 255 / 7), GifByteType((i & 3) * 255 / 3)};
  auto* file = EGifOpen(&output, WriteGif, &error);
  if (!file) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  EGifSetGifVersion(file, true);
  bool valid = EGifPutScreenDesc(file, frame.width, frame.height, 8, 0, palette.get()) == GIF_OK &&
      EGifPutImageDesc(file, 0, 0, frame.width, frame.height, false, nullptr) == GIF_OK;
  std::vector<GifPixelType> line(frame.width);
  for (int y = 0; valid && y < frame.height; ++y) {
    const auto* row = frame.bgra.data() + std::size_t(y) * frame.stride;
    for (int x = 0; x < frame.width; ++x)
      line[x] = GifPixelType((row[x * 4 + 2] & 0xe0) | ((row[x * 4 + 1] & 0xe0) >> 3) | (row[x * 4] >> 6));
    valid = EGifPutLine(file, line.data(), frame.width) == GIF_OK;
  }
  valid = EGifCloseFile(file, &error) == GIF_OK && valid;
  if (!valid || output.bytes.size() <= 792 || std::memcmp(output.bytes.data(), "GIF89a", 6) ||
      output.bytes[781] != 0x2c || output.bytes.back() != 0x3b)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  return std::move(output.bytes);
}
class Gif final : public Writer {
 public:
  Gif(std::filesystem::path path, Budget& budget) : budget_(budget) {
    output_.path = std::move(path); output_.mime_type = "image/gif";
  }
  bool Write(const ScriptFrame& frame, double, double end_ms, ScriptMediaFramePurpose) override {
    if (finished_) throw std::runtime_error("CAPTURE_ALREADY_FINISHED");
    const auto boundary = std::uint64_t(std::llround(end_ms / 10.0));
    if (boundary <= centiseconds_) { ++output_.dropped_frames; return true; }
    auto encoded = Encode(frame);
    const auto image_bytes = encoded.size() - 781 - 1;
    const auto intervals = (boundary - centiseconds_ + 65534) / 65535;
    const auto header = output_.frame_count ? 0 : 781 + 19 + 1; // Includes the final trailer.
    if (intervals > (budget_.limit - budget_.used) / (image_bytes + 8) ||
        !budget_.Take(header + std::size_t(intervals) * (image_bytes + 8))) {
      budget_.exceeded = true; ++output_.dropped_frames; return false;
    }
    if (!output_.frame_count) {
      bytes_.assign(encoded.begin(), encoded.begin() + 781);
      const std::uint8_t loop[] = {0x21,0xff,11,'N','E','T','S','C','A','P','E','2','.','0',3,1,0,0,0};
      bytes_.insert(bytes_.end(), std::begin(loop), std::end(loop));
      output_.width = frame.width; output_.height = frame.height;
    }
    auto remaining = boundary - centiseconds_;
    while (remaining) {
      const auto delay = std::min<std::uint64_t>(remaining, 65535);
      const std::uint8_t control[] = {0x21,0xf9,4,4,std::uint8_t(delay),std::uint8_t(delay >> 8),0,0};
      bytes_.insert(bytes_.end(), std::begin(control), std::end(control));
      bytes_.insert(bytes_.end(), encoded.begin() + 781, encoded.end() - 1);
      ++output_.frame_count; remaining -= delay;
    }
    ++committed_sources_;
    centiseconds_ = boundary; output_.duration_ms = boundary * 10.0; return true;
  }
  std::size_t CommittedSourceFrames() const override { return committed_sources_; }
  ScriptMediaOutput Finish() override {
    if (!finished_ && output_.frame_count) {
      bytes_.push_back(0x3b); WriteCaptureFile(output_.path, bytes_);
      bytes_.clear(); bytes_.shrink_to_fit();
    }
    finished_ = true; return output_;
  }
 private:
  Budget& budget_;
  ScriptMediaOutput output_;
  std::vector<std::uint8_t> bytes_;
  std::uint64_t centiseconds_ = 0;
  std::size_t committed_sources_ = 0;
  bool finished_ = false;
};
}
std::unique_ptr<Writer> MakeGif(const std::filesystem::path& path, Budget& budget) {
  return std::make_unique<Gif>(path, budget);
}
}
