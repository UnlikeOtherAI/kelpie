#include "script_media_internal.h"

#include <wincodec.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

namespace kelpie::windows::media {
namespace {

// WIC performs palette quantization and GIF/LZW compression. Framing the known
// compressed image ourselves lets us test its exact byte cost BEFORE appending,
// so a budget stop never leaves an unfinished frame or loses the GIF trailer.
std::vector<std::uint8_t> EncodeFrame(const ScriptMediaFrame& frame) {
  ComPtr<IWICImagingFactory> factory;
  Check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&factory)));
  ComPtr<IWICBitmap> bitmap;
  Check(factory->CreateBitmapFromMemory(frame.width, frame.height,
      GUID_WICPixelFormat32bppBGRA, Stride(frame),
      static_cast<UINT>(frame.bgra.size()), const_cast<BYTE*>(frame.bgra.data()), &bitmap));
  ComPtr<IWICPalette> palette;
  Check(factory->CreatePalette(&palette));
  Check(palette->InitializeFromBitmap(bitmap.Get(), 256, FALSE));
  ComPtr<IWICFormatConverter> converted;
  Check(factory->CreateFormatConverter(&converted));
  Check(converted->Initialize(bitmap.Get(), GUID_WICPixelFormat8bppIndexed,
      WICBitmapDitherTypeErrorDiffusion, palette.Get(), 0, WICBitmapPaletteTypeCustom));
  ComPtr<IStream> stream;
  Check(CreateStreamOnHGlobal(nullptr, TRUE, &stream));
  ComPtr<IWICBitmapEncoder> encoder;
  Check(factory->CreateEncoder(GUID_ContainerFormatGif, nullptr, &encoder));
  Check(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache));
  Check(encoder->SetPalette(palette.Get()));
  ComPtr<IWICBitmapFrameEncode> encoded;
  Check(encoder->CreateNewFrame(&encoded, nullptr));
  Check(encoded->Initialize(nullptr));
  Check(encoded->SetSize(frame.width, frame.height));
  auto format = GUID_WICPixelFormat8bppIndexed;
  Check(encoded->SetPixelFormat(&format));
  Check(encoded->SetPalette(palette.Get()));
  Check(encoded->WriteSource(converted.Get(), nullptr));
  Check(encoded->Commit());
  Check(encoder->Commit());
  STATSTG stats{};
  Check(stream->Stat(&stats, STATFLAG_NONAME));
  if (stats.cbSize.QuadPart > frame.bgra.size() * 2 + 65536)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  std::vector<std::uint8_t> result(static_cast<std::size_t>(stats.cbSize.QuadPart));
  LARGE_INTEGER start{};
  Check(stream->Seek(start, STREAM_SEEK_SET, nullptr));
  ULONG read = 0;
  Check(stream->Read(result.data(), static_cast<ULONG>(result.size()), &read));
  if (read != result.size()) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  return result;
}

std::size_t SkipBlocks(const std::vector<std::uint8_t>& bytes, std::size_t offset) {
  while (offset < bytes.size()) {
    const auto size = bytes[offset++];
    if (size == 0) return offset;
    if (size > bytes.size() - offset) break;
    offset += size;
  }
  throw std::runtime_error("CAPTURE_ENCODING_FAILED");
}

struct GifParts {
  std::vector<std::uint8_t> header;
  std::vector<std::uint8_t> image;
};

GifParts Parse(const std::vector<std::uint8_t>& bytes) {
  if (bytes.size() < 14 || std::memcmp(bytes.data(), "GIF8", 4) != 0)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  const auto global_size = (bytes[10] & 0x80) ? (3ULL << ((bytes[10] & 7) + 1)) : 0;
  const auto header_size = 13 + global_size;
  if (header_size >= bytes.size()) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  std::size_t offset = header_size;
  while (offset < bytes.size() && bytes[offset] == 0x21) {
    if (offset + 2 >= bytes.size()) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
    offset = SkipBlocks(bytes, offset + 2);
  }
  if (offset + 11 >= bytes.size() || bytes[offset] != 0x2c)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  GifParts result;
  result.header.assign(bytes.begin(), bytes.begin() + header_size);
  result.header[3] = '8';
  result.header[4] = '9';
  result.header[5] = 'a';
  result.image.assign(bytes.begin() + offset, bytes.begin() + offset + 10);
  const auto packed = bytes[offset + 9];
  const auto local_size = (packed & 0x80) ? (3ULL << ((packed & 7) + 1)) : 0;
  const auto data_start = offset + 10 + local_size;
  if (data_start >= bytes.size()) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  if (local_size) {
    result.image.insert(result.image.end(), bytes.begin() + offset + 10,
                        bytes.begin() + data_start);
  } else {
    if (!global_size) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
    result.image[9] = static_cast<std::uint8_t>((packed & 0x40) | 0x80 | (bytes[10] & 7));
    result.image.insert(result.image.end(), bytes.begin() + 13, bytes.begin() + header_size);
  }
  const auto end = SkipBlocks(bytes, data_start + 1);  // LZW minimum code size.
  result.image.insert(result.image.end(), bytes.begin() + data_start, bytes.begin() + end);
  return result;
}

class WicGif final : public GifWriter {
 public:
  WicGif(const std::filesystem::path& path, Budget& budget)
      : budget_(budget) {
    output_.path = path;
    output_.mime_type = "image/gif";
  }

  ~WicGif() override { if (file_ != INVALID_HANDLE_VALUE) Discard(); }

  bool Write(const ScriptMediaFrame& frame, double, double end_ms) override {
    const auto boundary = static_cast<std::uint64_t>(std::llround(end_ms / 10.0));
    if (boundary <= centiseconds_) {
      ++output_.dropped_frames;
      return true;  // Cannot represent an interval below GIF's 10 ms time unit.
    }
    const auto parts = Parse(EncodeFrame(frame));
    const auto intervals = (boundary - centiseconds_ + 65534) / 65535;
    const auto header_bytes = output_.frame_count == 0 ? parts.header.size() + 19 + 1 : 0;
    const auto bytes = header_bytes + intervals * (parts.image.size() + 8);
    if (!budget_.Take(static_cast<std::size_t>(bytes))) {
      ++output_.dropped_frames;
      return false;
    }
    if (file_ == INVALID_HANDLE_VALUE) {
      file_ = CreateFileW(output_.path.c_str(), GENERIC_WRITE | DELETE, FILE_SHARE_READ,
                          nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (file_ == INVALID_HANDLE_VALUE) {
        const auto error = GetLastError();
        if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS)
          throw std::runtime_error("CAPTURE_OUTPUT_EXISTS");
        throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
      }
      owns_file_ = true;
      WriteBytes(parts.header.data(), parts.header.size());
      const std::uint8_t loop[] = {0x21, 0xff, 11, 'N', 'E', 'T', 'S', 'C', 'A',
                                  'P', 'E', '2', '.', '0', 3, 1, 0, 0, 0};
      WriteBytes(loop, sizeof(loop));
      output_.width = frame.width;
      output_.height = frame.height;
    }
    auto remaining = boundary - centiseconds_;
    while (remaining) {
      const auto delay = std::min<std::uint64_t>(remaining, 65535);
      const std::uint8_t control[] = {
          0x21, 0xf9, 4, 4, static_cast<std::uint8_t>(delay),
          static_cast<std::uint8_t>(delay >> 8), 0, 0};
      WriteBytes(control, sizeof(control));
      WriteBytes(parts.image.data(), parts.image.size());
      remaining -= delay;
      ++output_.frame_count;
    }
    centiseconds_ = boundary;
    output_.duration_ms = static_cast<double>(boundary) * 10;
    ++committed_frames_;
    return true;
  }

  ScriptMediaOutput Finish() override {
    if (failed_) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
    if (file_ != INVALID_HANDLE_VALUE) {
      const std::uint8_t trailer = 0x3b;
      WriteBytes(&trailer, 1);  // Reserved with first frame, including budget stop.
      if (!FlushFileBuffers(file_)) {
        Discard();
        throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
      }
      if (!CloseHandle(file_)) {
        Discard();
        throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
      }
      file_ = INVALID_HANDLE_VALUE;
    }
    return output_;
  }

  std::size_t BytesWritten() const override {
    return owns_file_ ? FileBytes(output_.path) : 0;
  }

  std::size_t CommittedFrames() const override { return committed_frames_; }
 private:
  std::size_t committed_frames_=0;
  void Discard() noexcept {
    FILE_DISPOSITION_INFO discard{TRUE};
    SetFileInformationByHandle(file_, FileDispositionInfo, &discard, sizeof(discard));
    CloseHandle(file_);
    file_ = INVALID_HANDLE_VALUE;
    owns_file_ = false;
    failed_ = true;
  }

  void WriteBytes(const std::uint8_t* bytes, std::size_t count) {
    DWORD written = 0;
    if (!WriteFile(file_, bytes, static_cast<DWORD>(count), &written, nullptr) ||
        written != count) {
      Discard();
      throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
    }
  }

  Budget& budget_;
  HANDLE file_ = INVALID_HANDLE_VALUE;
  bool owns_file_ = false;
  bool failed_ = false;
  ScriptMediaOutput output_;
  std::uint64_t centiseconds_ = 0;
};
}  // namespace

std::unique_ptr<GifWriter> CreateGif(const std::filesystem::path& path, Budget& budget) {
  return std::make_unique<WicGif>(path, budget);
}
}  // namespace kelpie::windows::media