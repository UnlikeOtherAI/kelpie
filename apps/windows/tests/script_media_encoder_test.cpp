#include "script_media_encoder.h"
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <thread>

using Microsoft::WRL::ComPtr;
using namespace kelpie::windows;
namespace fs = std::filesystem;

namespace {
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
void Check(HRESULT result) {
  if (FAILED(result)) {
    std::cerr << "HRESULT: 0x" << std::hex << result << std::dec << std::endl;
    throw std::runtime_error("native API failed");
  }
}
template <class F> void Throws(F&& operation, const char* code) {
  try { operation(); } catch (const std::runtime_error& error) {
    Require(std::string(error.what()) == code, "unexpected error code");
    return;
  }
  throw std::runtime_error("expected rejection");
}
ScriptMediaFrame Frame(double time, int width = 64, int height = 48, bool noise = false) {
  ScriptMediaFrame frame{width, height, width * 4, {}, time};
  frame.bgra.resize(static_cast<std::size_t>(width) * height * 4);
  std::uint32_t random = 12345 + static_cast<std::uint32_t>(time);
  for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
    const auto offset = (static_cast<std::size_t>(y) * width + x) * 4;
    for (int channel = 0; channel < 3; ++channel) {
      random ^= random << 13; random ^= random >> 17; random ^= random << 5;
      frame.bgra[offset + channel] = noise ? static_cast<BYTE>(random) : 0;
    }
    if (!noise) frame.bgra[offset + (y < height / 2 ? 2 : 0)] = 255;
    frame.bgra[offset + 3] = 255;
  }
  return frame;
}
ComPtr<IWICBitmapDecoder> Image(const fs::path& path) {
  ComPtr<IWICImagingFactory> factory;
  Check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)));
  ComPtr<IWICBitmapDecoder> decoder;
  Check(factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad, &decoder));
  return decoder;
}
void Pixels(IWICBitmapSource* image, bool colors) {
  ComPtr<IWICImagingFactory> factory;
  Check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)));
  ComPtr<IWICFormatConverter> converter;
  Check(factory->CreateFormatConverter(&converter));
  Check(converter->Initialize(image, GUID_WICPixelFormat32bppBGRA,
      WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom));
  UINT width = 0, height = 0;
  Check(image->GetSize(&width, &height));
  std::vector<BYTE> pixels(width * height * 4);
  Check(converter->CopyPixels(nullptr, width * 4, static_cast<UINT>(pixels.size()), pixels.data()));
  if (colors) {
    Require(width == 64 && height == 48, "wrong image size");
    Require(pixels[2] > 200 && pixels[0] < 40, "top red pixel changed/flipped");
    const auto bottom = (height - 1) * width * 4;
    Require(pixels[bottom] > 200 && pixels[bottom + 2] < 40, "bottom blue pixel changed/flipped");
  }
}
void Decode(const ScriptMediaOutput& output, bool colors) {
  if (output.mime_type == "image/gif") {
    auto decoder = Image(output.path);
    UINT count = 0;
    Check(decoder->GetFrameCount(&count));
    Require(count == output.frame_count && count, "wrong GIF frame count");
    std::uint64_t duration = 0;
    for (UINT index = 0; index < count; ++index) {
      ComPtr<IWICBitmapFrameDecode> frame;
      Check(decoder->GetFrame(index, &frame));
      ComPtr<IWICMetadataQueryReader> metadata;
      Check(frame->GetMetadataQueryReader(&metadata));
      PROPVARIANT value{};
      Check(metadata->GetMetadataByName(L"/grctlext/Delay", &value));
      Require(value.vt == VT_UI2 && value.uiVal > 0, "invalid GIF delay");
      duration += value.uiVal * 10;
      PropVariantClear(&value);
      Pixels(frame.Get(), colors);
    }
    Require(std::abs(static_cast<double>(duration) - output.duration_ms) < 0.1, "wrong GIF duration");
    return;
  }
  ComPtr<IMFSourceReader> reader;
  Check(MFCreateSourceReaderFromURL(output.path.c_str(), nullptr, &reader));
  ComPtr<IMFMediaType> type;
  Check(MFCreateMediaType(&type));
  Check(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
  Check(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12));
  Check(reader->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr, type.Get()));
  Check(reader->GetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &type));
  UINT width = 0, height = 0;
  Check(MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &width, &height));
  Require(width == static_cast<UINT>(output.width) && height == static_cast<UINT>(output.height), "wrong MP4 dimensions");
  UINT32 stride = width;
  type->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride);
  std::size_t count = 0;
  LONGLONG last = -1;
  for (;;) {
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    ComPtr<IMFSample> sample;
    Check(reader->ReadSample(static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, nullptr, &flags, &timestamp, &sample));
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    Require(timestamp > last, "non-monotonic MP4 sample");
    last = timestamp;
    ComPtr<IMFMediaBuffer> buffer;
    Check(sample->ConvertToContiguousBuffer(&buffer));
    BYTE* bytes = nullptr;
    DWORD length = 0;
    Check(buffer->Lock(&bytes, nullptr, &length));
    Require(length >= width * height * 3 / 2, "short decoded MP4 frame");
    if (colors) {
      Require(bytes[0] > 65 && bytes[0] < 100, "top MP4 row is not red");
      Require(bytes[(height - 1) * stride] < 60, "bottom MP4 row is not blue");
    }
    Check(buffer->Unlock());
    ++count;
  }
  Require(count == output.frame_count && count, "MP4 not fully decodable");
  PROPVARIANT duration{};
  Check(reader->GetPresentationAttribute(static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION, &duration));
  Require(duration.vt == VT_UI8 &&
      std::abs(static_cast<double>(duration.uhVal.QuadPart) / 10000 - output.duration_ms) < 2, "wrong MP4 duration");
  PropVariantClear(&duration);
}
fs::path Child(const fs::path& root, const char* name) {
  const auto path = root / name;
  fs::create_directory(path);
  return path;
}
void Timing(const fs::path& root) {
  const auto directory = Child(root, "timing");
  auto encoder = ScriptMediaEncoder::Create(directory, {"gif", "mp4"}, 30);
  Require(encoder->AddFrame(Frame(100)), "first frame rejected");
  Require(encoder->AddFrame(Frame(237)), "second frame rejected");
  Require(encoder->AddFrame(Frame(690)), "third frame rejected");
  Require(encoder->WriteStepPNG(Frame(0), directory / "step.png"), "step PNG rejected");
  ScriptMediaEncoder::WritePNG(Frame(0), directory / "independent.png");
  auto png = Image(directory / "step.png");
  ComPtr<IWICBitmapFrameDecode> frame;
  Check(png->GetFrame(0, &frame));
  Pixels(frame.Get(), true);
  const auto outputs = encoder->Finish(1111);
  Require(outputs.size() == 2 && !encoder->budget_exceeded(), "missing format");
  Require(encoder->Finish(0).size() == 2, "Finish not idempotent");
  for (const auto& output : outputs) {
    Require(output.frame_count == 3, "wrong timed frame count");
    Require(std::abs(output.duration_ms - 1011) <= 5, "cumulative timing drift");
    Decode(output, true);
  }
  Throws([&] { encoder->AddFrame(Frame(2000)); }, "CAPTURE_ALREADY_FINISHED");
  Throws([&] { ScriptMediaEncoder::Create(directory, {"gif"}, 30); }, "CAPTURE_OUTPUT_EXISTS");
  std::cout << "GIF/MP4/PNG decoded: frame timing, dimensions, colors and orientation passed" << std::endl;
}
void AbortAndValidation(const fs::path& root) {
  const auto directory = Child(root, "validation");
  Throws([&] { ScriptMediaEncoder::Create(directory, {"webm"}, 30); }, "CAPTURE_INVALID_OPTIONS");
  auto encoder = ScriptMediaEncoder::Create(directory, {"gif", "mp4"}, 30);
  auto invalid = Frame(0);
  invalid.bgra.pop_back();
  Throws([&] { encoder->AddFrame(invalid); }, "CAPTURE_INVALID_FRAME");
  Throws([&] { encoder->AddFrame(Frame(0, 63)); }, "CAPTURE_VIDEO_REQUIRES_EVEN_SIZE");
  Require(encoder->AddFrame(Frame(0)), "abort first frame rejected");
  Throws([&] { encoder->AddFrame(Frame(0)); }, "CAPTURE_INVALID_FRAME");
  Throws([&] { encoder->AddFrame(Frame(10, 32)); }, "CAPTURE_INVALID_FRAME");
  Throws([&] { encoder->Finish(0); }, "CAPTURE_INVALID_TIMESTAMP");
  auto nan = Frame(1);
  nan.elapsed_ms = std::numeric_limits<double>::quiet_NaN();
  Throws([&] { encoder->AddFrame(nan); }, "CAPTURE_INVALID_FRAME");
  std::thread wrong([&] { Throws([&] { encoder->bytes_written(); }, "CAPTURE_WRONG_THREAD"); });
  wrong.join();
  const auto outputs = encoder->Finish(37);
  Require(outputs.size() == 2, "Stop lost first-frame output");
  for (const auto& output : outputs) Decode(output, true);
  auto next = ScriptMediaEncoder::Create(Child(root, "after-abort"), {"mp4"}, 30);
  next->AddFrame(Frame(0));
  Decode(next->Finish(100).front(), true);
  auto empty = ScriptMediaEncoder::Create(Child(root, "empty"), {"gif", "mp4"}, 30);
  Require(empty->Finish(0).empty(), "empty capture generated files");
  std::cout << "validation, owner thread, Stop partial output and next capture passed" << std::endl;
}
void Budget(const fs::path& root, const char* format) {
  constexpr std::size_t budget = 1024 * 1024;
  auto encoder = ScriptMediaEncoder::Create(Child(root, format), {format}, 1, budget);
  bool accepted = true;
  int index = 0;
  for (; index < 250 && accepted; ++index)
    accepted = encoder->AddFrame(Frame(index * 1000.0, 256, 192, true));
  Require(!accepted && encoder->budget_exceeded(), "budget did not stop capture");
  const auto outputs = encoder->Finish(index * 1000.0);
  Require(outputs.size() == 1, "budget lost partial output");
  Require(encoder->bytes_written() <= budget, "output exceeded byte cap");
  Require(outputs[0].dropped_frames > 0, "missing dropped frame count");
  Decode(outputs[0], false);
  std::cout << format << " valid budget partial: " << outputs[0].frame_count
            << " frames, " << encoder->bytes_written() << " bytes" << std::endl;
}
void StepBudget(const fs::path& root) {
  constexpr std::size_t limit = 1024 * 1024;
  const auto directory = Child(root, "step-budget");
  auto encoder = ScriptMediaEncoder::Create(directory, {"gif", "mp4"}, 30, limit);
  encoder->AddFrame(Frame(0));
  encoder->AddFrame(Frame(50));
  Require(encoder->WriteStepPNG(Frame(60, 256, 192, true), directory / "step.png"),
          "bounded screenshot rejected");
  Throws([&] { encoder->WriteStepPNG(Frame(61), directory / "capture.mp4"); },
         "CAPTURE_INVALID_ARTIFACT_PATH");
  Require(!encoder->WriteStepPNG(Frame(70, 1024, 768, true), directory / "too-large.png"),
          "oversized PNG admitted");
  Require(!fs::exists(directory / "too-large.png"), "rejected PNG wrote bytes");
  Require(!encoder->AddFrame(Frame(90)), "budget stop was not sticky");
  const auto outputs = encoder->Finish(100);
  Require(outputs.size() == 2, "PNG budget stop lost previous media");
  for (const auto& output : outputs) Decode(output, true);
  Require(encoder->bytes_written() <= limit, "combined media/PNG exceeded budget");
  std::uintmax_t actual = 0;
  for (const auto& file : fs::directory_iterator(directory)) actual += file.file_size();
  Require(actual == encoder->bytes_written(), "retained byte accounting differs from disk");
  auto png = Image(directory / "step.png");
  ComPtr<IWICBitmapFrameDecode> frame;
  Check(png->GetFrame(0, &frame));
  Pixels(frame.Get(), false);
  std::cout << "shared PNG/GIF/MP4 budget: " << actual << " retained bytes; rejected PNG absent" << std::endl;
}
void GifRounding(const fs::path& root) {
  auto encoder = ScriptMediaEncoder::Create(Child(root, "rounding"), {"gif"}, 60);
  for (int index = 0; index < 60; ++index)
    encoder->AddFrame(Frame(index * 1000.0 / 60));
  const auto outputs = encoder->Finish(1000);
  Require(outputs.front().duration_ms == 1000, "GIF rounding accumulated drift");
  Decode(outputs.front(), true);
  auto held = ScriptMediaEncoder::Create(Child(root, "held"), {"gif"}, 1);
  held->AddFrame(Frame(0));
  const auto long_output = held->Finish(700000);
  Require(long_output.front().frame_count == 2 && long_output.front().duration_ms == 700000,
          "long GIF hold did not split delay safely");
  Decode(long_output.front(), true);
  std::cout << "GIF cumulative rounding and long final hold passed" << std::endl;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    Require(argc == 2, "provide fresh artifact directory");
    const fs::path root(argv[1]);
    Require(!fs::exists(root), "artifact directory must be new");
    fs::create_directories(root);
    Check(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
    Check(MFStartup(MF_VERSION));
    Timing(root);
    AbortAndValidation(root);
    Budget(root, "gif");
    Budget(root, "mp4");
    StepBudget(root);
    GifRounding(root);
    PROCESS_MEMORY_COUNTERS memory{};
    Check(GetProcessMemoryInfo(GetCurrentProcess(), &memory, sizeof(memory)) ? S_OK : E_FAIL);
    std::cout << "Peak working set bytes: " << memory.PeakWorkingSetSize
              << "; peak committed bytes: " << memory.PeakPagefileUsage << std::endl;
    MFShutdown();
    CoUninitialize();
    std::cout << "All native media encoder checks passed" << std::endl;
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}