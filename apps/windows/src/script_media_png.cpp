#include "script_media_internal.h"

#include <wincodec.h>

namespace kelpie::windows::media {
namespace {
struct ComScope {
  HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  ComScope() {
    if (FAILED(result) && result != RPC_E_CHANGED_MODE)
      throw std::runtime_error("CAPTURE_COM_UNAVAILABLE");
  }
  ~ComScope() { if (SUCCEEDED(result)) CoUninitialize(); }
};
}  // namespace

std::vector<std::uint8_t> EncodePNG(const ScriptMediaFrame& frame) {
  ValidateFrame(frame);
  ComScope com;
  ComPtr<IWICImagingFactory> factory;
  Check(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&factory)));
  ComPtr<IStream> stream;
  Check(CreateStreamOnHGlobal(nullptr, TRUE, &stream));
  ComPtr<IWICBitmapEncoder> encoder;
  Check(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder));
  Check(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache));
  ComPtr<IWICBitmapFrameEncode> encoded;
  Check(encoder->CreateNewFrame(&encoded, nullptr));
  Check(encoded->Initialize(nullptr));
  Check(encoded->SetSize(frame.width, frame.height));
  auto format = GUID_WICPixelFormat32bppBGRA;
  Check(encoded->SetPixelFormat(&format));
  if (format != GUID_WICPixelFormat32bppBGRA)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  Check(encoded->WritePixels(frame.height, Stride(frame),
      static_cast<UINT>(frame.bgra.size()), const_cast<BYTE*>(frame.bgra.data())));
  Check(encoded->Commit());
  Check(encoder->Commit());
  STATSTG stats{};
  Check(stream->Stat(&stats, STATFLAG_NONAME));
  if (stats.cbSize.QuadPart > frame.bgra.size() * 2 + 65536)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  std::vector<std::uint8_t> bytes(static_cast<std::size_t>(stats.cbSize.QuadPart));
  LARGE_INTEGER start{};
  Check(stream->Seek(start, STREAM_SEEK_SET, nullptr));
  ULONG count = 0;
  Check(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &count));
  if (count != bytes.size()) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  return bytes;
}

void WritePNGBytes(const std::vector<std::uint8_t>& bytes, const std::filesystem::path& path,
                   const PngFileOps& io) {
  const auto file = CreateFileW(path.c_str(), GENERIC_WRITE | DELETE, 0, nullptr, CREATE_NEW,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    if (GetLastError() == ERROR_FILE_EXISTS)
      throw std::runtime_error("CAPTURE_OUTPUT_EXISTS");
    throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
  }
  // Keep a second handle to this exact newly-created file until close succeeds.
  // Cleanup never follows a path that another producer could replace.
  HANDLE guard = INVALID_HANDLE_VALUE;
  if (!DuplicateHandle(GetCurrentProcess(), file, GetCurrentProcess(), &guard,
                       0, FALSE, DUPLICATE_SAME_ACCESS)) {
    FILE_DISPOSITION_INFO discard{TRUE};
    SetFileInformationByHandle(file, FileDispositionInfo, &discard, sizeof(discard));
    CloseHandle(file);
    throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
  }
  DWORD written = 0;
  const auto success = io.write(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
  const auto closed = io.close(file);
  if (!success || !closed || written != bytes.size()) {
    FILE_DISPOSITION_INFO discard{TRUE};
    SetFileInformationByHandle(guard, FileDispositionInfo, &discard, sizeof(discard));
    if (!closed) CloseHandle(file);
    CloseHandle(guard);
    throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE");
  }
  CloseHandle(guard);
}}  // namespace kelpie::windows::media

namespace kelpie::windows {
void ScriptMediaEncoder::WritePNG(
    const ScriptMediaFrame& frame, const std::filesystem::path& path) {
  media::WritePNGBytes(media::EncodePNG(frame), path);
}
}  // namespace kelpie::windows