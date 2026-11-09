#include "site_preview_codec.h"

#include <cstdint>
#include <vector>

#include "include/cef_image.h"
#include "site_preview_image.h"

namespace kelpie::site_preview {
namespace {

constexpr int kJpegQuality = 82;

bool IsPng(const std::vector<std::uint8_t>& bytes) {
  return bytes.size() > 8 && bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G';
}

}  // namespace

// CefImage may be used on any browser-process thread, which is what lets the
// capture worker decode and encode without hopping to the CEF UI thread.
std::optional<std::string> EncodePreview(const std::string& capture_base64) {
  const auto encoded = DecodeBase64(capture_base64);
  if (!encoded || encoded->empty()) return std::nullopt;
  CefRefPtr<CefImage> capture = CefImage::CreateImage();
  const bool added = IsPng(*encoded) ? capture->AddPNG(1.0F, encoded->data(), encoded->size())
                                     : capture->AddJPEG(1.0F, encoded->data(), encoded->size());
  if (!added) return std::nullopt;

  int width = 0;
  int height = 0;
  const CefRefPtr<CefBinaryValue> bitmap =
      capture->GetAsBitmap(1.0F, CEF_COLOR_TYPE_BGRA_8888, CEF_ALPHA_TYPE_OPAQUE, width, height);
  if (!bitmap || width <= 0 || height <= 0 ||
      bitmap->GetSize() != static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U) {
    return std::nullopt;
  }
  std::vector<std::uint8_t> pixels(bitmap->GetSize());
  if (bitmap->GetData(pixels.data(), pixels.size(), 0) != pixels.size()) return std::nullopt;

  const PixelRect crop = PreviewCrop(width, height);
  const PixelRect size = PreviewSize(crop);
  const auto scaled = Downscale(pixels, width, height, crop, size.width, size.height);
  if (scaled.empty() || LooksBlank(scaled, size.width, size.height)) return std::nullopt;

  CefRefPtr<CefImage> preview = CefImage::CreateImage();
  if (!preview->AddBitmap(1.0F, size.width, size.height, CEF_COLOR_TYPE_BGRA_8888, CEF_ALPHA_TYPE_OPAQUE,
                          scaled.data(), scaled.size())) {
    return std::nullopt;
  }
  int jpeg_width = 0;
  int jpeg_height = 0;
  const CefRefPtr<CefBinaryValue> jpeg = preview->GetAsJPEG(1.0F, kJpegQuality, jpeg_width, jpeg_height);
  if (!jpeg || jpeg->GetSize() == 0) return std::nullopt;
  std::string bytes(jpeg->GetSize(), '\0');
  if (jpeg->GetData(bytes.data(), bytes.size(), 0) != bytes.size()) return std::nullopt;
  return bytes;
}

}  // namespace kelpie::site_preview
