#include "script_media_internal.h"
#include "script_media_owned_file.h"

#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mftransform.h>
#include <wmcodecdsp.h>
#include <algorithm>
#include <cmath>
#include <deque>

namespace kelpie::windows::media {
namespace {

ComPtr<IMFMediaType> VideoType(const GUID& subtype, int width, int height, int fps) {
  ComPtr<IMFMediaType> type;
  Check(MFCreateMediaType(&type));
  Check(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
  Check(type->SetGUID(MF_MT_SUBTYPE, subtype));
  Check(type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive));
  Check(MFSetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, width, height));
  Check(MFSetAttributeRatio(type.Get(), MF_MT_FRAME_RATE, fps, 1));
  Check(MFSetAttributeRatio(type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1));
  Check(type->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT601));
  Check(type->SetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235));
  return type;
}

BYTE Clamp(int value) { return static_cast<BYTE>(std::clamp(value, 0, 255)); }

// Native H.264 input is NV12, not RGB. Use a fixed BT.601 limited-range transform
// and average each 2x2 chroma block. Rows remain top-down; no GDI stride flip.
ComPtr<IMFSample> InputSample(
    const ScriptMediaFrame& frame, LONGLONG start, LONGLONG duration) {
  const auto count = static_cast<DWORD>(frame.width * frame.height * 3 / 2);
  ComPtr<IMFMediaBuffer> buffer;
  Check(MFCreateMemoryBuffer(count, &buffer));
  BYTE* pixels = nullptr;
  Check(buffer->Lock(&pixels, nullptr, nullptr));
  const auto stride = Stride(frame);
  const auto plane = frame.width * frame.height;
  for (int y = 0; y < frame.height; ++y) {
    for (int x = 0; x < frame.width; ++x) {
      const auto* source = frame.bgra.data() + static_cast<std::size_t>(y) * stride + x * 4;
      pixels[y * frame.width + x] =
          Clamp(((66 * source[2] + 129 * source[1] + 25 * source[0] + 128) >> 8) + 16);
    }
  }
  for (int y = 0; y < frame.height; y += 2) {
    for (int x = 0; x < frame.width; x += 2) {
      int red = 0, green = 0, blue = 0;
      for (int dy = 0; dy < 2; ++dy) {
        for (int dx = 0; dx < 2; ++dx) {
          const auto* source = frame.bgra.data() +
              static_cast<std::size_t>(y + dy) * stride + (x + dx) * 4;
          blue += source[0];
          green += source[1];
          red += source[2];
        }
      }
      red = (red + 2) / 4; green = (green + 2) / 4; blue = (blue + 2) / 4;
      const auto offset = plane + (y / 2) * frame.width + x;
      pixels[offset] = Clamp(((-38 * red - 74 * green + 112 * blue + 128) >> 8) + 128);
      pixels[offset + 1] = Clamp(((112 * red - 94 * green - 18 * blue + 128) >> 8) + 128);
    }
  }
  Check(buffer->Unlock());
  Check(buffer->SetCurrentLength(count));
  ComPtr<IMFSample> sample;
  Check(MFCreateSample(&sample));
  Check(sample->AddBuffer(buffer.Get()));
  Check(sample->SetSampleTime(start));
  Check(sample->SetSampleDuration(duration));
  return sample;
}

class MfVideo final : public VideoWriter {
 public:
  MfVideo(const std::filesystem::path& path, int width, int height, int fps, Budget& budget)
      : budget_(budget) {
    output_.path = path;
    output_.mime_type = "video/mp4";
    output_.width = width;
    output_.height = height;
    Check(CoCreateInstance(CLSID_CMSH264EncoderMFT, nullptr, CLSCTX_INPROC_SERVER,
                           IID_PPV_ARGS(&encoder_)), "CAPTURE_VIDEO_UNAVAILABLE");
    ComPtr<ICodecAPI> codec;
    Check(encoder_.As(&codec), "CAPTURE_VIDEO_UNAVAILABLE");
    VARIANT low_latency{};
    low_latency.vt = VT_BOOL;
    low_latency.boolVal = VARIANT_TRUE;
    Check(codec->SetValue(&CODECAPI_AVLowLatencyMode, &low_latency), "CAPTURE_VIDEO_UNAVAILABLE");
    auto compressed = VideoType(MFVideoFormat_H264, width, height, fps);
    const auto bitrate = static_cast<UINT32>(
        std::clamp<std::uint64_t>(static_cast<std::uint64_t>(width) * height * fps / 8,
                                  256000, 12000000));
    Check(compressed->SetUINT32(MF_MT_AVG_BITRATE, bitrate));
    // Baseline has no B-frames: presentation/output order stays identical and
    // retained timing metadata cannot become an unbounded reorder queue.
    Check(compressed->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Base));
    Check(encoder_->SetOutputType(0, compressed.Get(), 0), "CAPTURE_VIDEO_UNAVAILABLE");
    auto input = VideoType(MFVideoFormat_NV12, width, height, fps);
    Check(input->SetUINT32(MF_MT_DEFAULT_STRIDE, width));
    Check(encoder_->SetInputType(0, input.Get(), 0), "CAPTURE_VIDEO_UNAVAILABLE");
    Check(encoder_->GetOutputCurrentType(0, &encoded_type_));
    Check(encoder_->GetOutputStreamInfo(0, &stream_info_));
    const auto largest_sample = static_cast<std::size_t>(width) * height * 4 + 65536;
    if (stream_info_.cbSize == 0 || stream_info_.cbSize > largest_sample)
      throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
    Check(encoder_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0));
    Check(encoder_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0));
  }

  ~MfVideo() override { Discard(); }

  std::size_t CommittedFrames() const override { return output_.frame_count; }

  bool Write(const ScriptMediaFrame& frame, double start_ms, double end_ms) override {
    if (budget_.exceeded) return false;
    const auto start = static_cast<LONGLONG>(std::llround(start_ms * 10000));
    const auto end = static_cast<LONGLONG>(std::llround(end_ms * 10000));
    if (end <= start) throw std::runtime_error("CAPTURE_INVALID_TIMESTAMP");
    auto sample = InputSample(frame, start, end - start);
    auto result = encoder_->ProcessInput(0, sample.Get(), 0);
    if (result == MF_E_NOTACCEPTING) {
      Pump();
      if (budget_.exceeded) return false;
      result = encoder_->ProcessInput(0, sample.Get(), 0);
    }
    Check(result);
    timings_.push_back({start, end - start});
    if (timings_.size() > 16) throw std::runtime_error("CAPTURE_VIDEO_BUFFER_LIMIT");
    Pump();
    return !budget_.exceeded;
  }

  ScriptMediaOutput Finish() override {
    try {
      Check(encoder_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0));
      Check(encoder_->ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0));
      Pump();
      if (!timings_.empty()) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
      if (writer_) {
        Check(writer_->Finalize());
        writer_.Reset();
        Check(file_->Close(), "CAPTURE_OUTPUT_UNAVAILABLE");
        file_.Reset();
        Check(owned_stream_->Complete(), "CAPTURE_OUTPUT_UNAVAILABLE");
      }
      completed_ = true;
      return output_;
    } catch (...) {
      Discard();
      throw;
    }
  }

  std::size_t BytesWritten() const override {
    return owns_file_ ? FileBytes(output_.path) : 0;
  }

 private:
  void Discard() noexcept {
    writer_.Reset();
    if (file_) {
      // Failure cleanup still attempts identity-bound rollback if Close fails.
      const auto result = file_->Close();
      file_.Reset();
      if (FAILED(result)) owns_file_ = false;
    }
    if (owned_stream_ && !completed_) owned_stream_->Abort();
    if (!completed_) owns_file_ = false;
  }

  void OpenWriter() {
    owned_stream_.Attach(new OwnedMediaStream(output_.path));
    owns_file_ = true;
    try {
      // Wrap the exact exclusive file handle; MF never opens its path.
      Check(MFCreateMFByteStreamOnStream(owned_stream_.Get(), &file_));
      Check(MFCreateSinkWriterFromURL(output_.path.c_str(), file_.Get(), nullptr, &writer_));
      Check(writer_->AddStream(encoded_type_.Get(), &stream_));
      // Same compressed subtype means remux only; no implicit transcoding or
      // hidden raw-frame encoder queue in the sink writer.
      Check(writer_->SetInputMediaType(stream_, encoded_type_.Get(), nullptr));
      Check(writer_->BeginWriting());
    } catch (...) {
      Discard();
      throw;
    }
  }

  void Retain(IMFSample* sample) {
    if (timings_.empty()) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
    const auto timing = timings_.front();
    timings_.pop_front();
    Check(sample->SetSampleTime(timing.start));
    Check(sample->SetSampleDuration(timing.duration));
    DWORD length = 0;
    Check(sample->GetTotalLength(&length));
    // Reserve Annex-B-to-AVCC expansion, per-sample tables, and 64 KiB fixed
    // container/footer space before accepting compressed bytes. Even a budget
    // stop drains the transform, discards excess samples and finalizes the sink.
    const auto reserve = static_cast<std::size_t>(length) * 2 + 512 +
                         (output_.frame_count == 0 ? 65536 : 0);
    if (budget_.exceeded || !budget_.Take(reserve)) {
      ++output_.dropped_frames;
      return;
    }
    if (!writer_) OpenWriter();
    Check(writer_->WriteSample(stream_, sample));
    ++output_.frame_count;
    output_.duration_ms = static_cast<double>(timing.start + timing.duration) / 10000;
  }

  void Pump() {
    for (;;) {
      ComPtr<IMFSample> sample;
      Check(MFCreateSample(&sample));
      ComPtr<IMFMediaBuffer> buffer;
      Check(MFCreateMemoryBuffer(stream_info_.cbSize, &buffer));
      Check(sample->AddBuffer(buffer.Get()));
      MFT_OUTPUT_DATA_BUFFER result{};
      result.pSample = sample.Get();
      DWORD status = 0;
      const auto hr = encoder_->ProcessOutput(0, 1, &result, &status);
      if (result.pEvents) result.pEvents->Release();
      if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) break;
      Check(hr);
      Retain(sample.Get());
    }
  }

  struct Timing { LONGLONG start; LONGLONG duration; };
  Budget& budget_;
  ComPtr<IMFTransform> encoder_;
  ComPtr<IMFMediaType> encoded_type_;
  ComPtr<IMFSinkWriter> writer_;
  ComPtr<IMFByteStream> file_;
  bool owns_file_ = false;
  bool completed_ = false;
  ComPtr<OwnedMediaStream> owned_stream_;
  MFT_OUTPUT_STREAM_INFO stream_info_{};
  DWORD stream_ = 0;
  std::deque<Timing> timings_;
  ScriptMediaOutput output_;
};
}  // namespace

std::unique_ptr<VideoWriter> CreateVideo(
    const std::filesystem::path& path, int width, int height, int fps, Budget& budget) {
  return std::make_unique<MfVideo>(path, width, height, fps, budget);
}
}  // namespace kelpie::windows::media