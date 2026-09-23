#include "desktop_screenshot_planner.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

namespace kelpie::desktop_screenshot {
namespace {

// A header sits in the first few hundred bytes of an image Chromium encodes,
// which writes no EXIF block ahead of the JPEG frame header.
constexpr std::size_t kHeaderBytes = 64 * 1024;

std::optional<std::string> ReadBoundedInteger(const Json& params, const char* key, int minimum,
                                              int maximum, std::optional<int>* output) {
  const auto it = params.find(key);
  if (it == params.end()) return std::nullopt;
  const std::string message = std::string(key) + " must be an integer between " +
                              std::to_string(minimum) + " and " + std::to_string(maximum);
  if (!it->is_number_integer()) return message;
  // Widen first: nlohmann narrows a large whole number to int silently, so
  // 4294967297 would arrive as 1 and pass the range check.
  if (it->is_number_unsigned() && it->get<std::uint64_t>() > static_cast<std::uint64_t>(maximum)) {
    return message;
  }
  const std::int64_t value = it->get<std::int64_t>();
  if (value < minimum || value > maximum) return message;
  *output = static_cast<int>(value);
  return std::nullopt;
}

std::optional<double> Number(const Json& object, const char* key) {
  const auto it = object.find(key);
  if (it == object.end() || !it->is_number()) return std::nullopt;
  const double value = it->get<double>();
  return std::isfinite(value) ? std::optional<double>(value) : std::nullopt;
}

int Base64Value(char ch) {
  if (ch >= 'A' && ch <= 'Z') return ch - 'A';
  if (ch >= 'a' && ch <= 'z') return ch - 'a' + 26;
  if (ch >= '0' && ch <= '9') return ch - '0' + 52;
  if (ch == '+') return 62;
  if (ch == '/') return 63;
  return -1;
}

std::optional<std::vector<std::uint8_t>> DecodePrefix(std::string_view base64, std::size_t limit) {
  std::vector<std::uint8_t> bytes;
  bytes.reserve(std::min(limit, base64.size() * 3 / 4));
  std::uint32_t buffer = 0;
  int bits = 0;
  for (const char ch : base64) {
    if (bytes.size() >= limit || ch == '=') break;
    const int value = Base64Value(ch);
    if (value < 0) return std::nullopt;
    buffer = ((buffer << 6) | static_cast<std::uint32_t>(value)) & 0xFFFFFFU;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push_back(static_cast<std::uint8_t>((buffer >> bits) & 0xFFU));
    }
  }
  return bytes;
}

std::uint32_t BigEndian32(const std::vector<std::uint8_t>& bytes, std::size_t offset) {
  return (static_cast<std::uint32_t>(bytes[offset]) << 24U) |
         (static_cast<std::uint32_t>(bytes[offset + 1]) << 16U) |
         (static_cast<std::uint32_t>(bytes[offset + 2]) << 8U) |
         static_cast<std::uint32_t>(bytes[offset + 3]);
}

std::uint16_t BigEndian16(const std::vector<std::uint8_t>& bytes, std::size_t offset) {
  return static_cast<std::uint16_t>((bytes[offset] << 8U) | bytes[offset + 1]);
}

std::optional<ImageHeader> PngHeader(const std::vector<std::uint8_t>& bytes) {
  static constexpr std::uint8_t kSignature[] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
  if (bytes.size() < 24) return std::nullopt;
  for (std::size_t index = 0; index < sizeof(kSignature); ++index) {
    if (bytes[index] != kSignature[index]) return std::nullopt;
  }
  if (bytes[12] != 'I' || bytes[13] != 'H' || bytes[14] != 'D' || bytes[15] != 'R') return std::nullopt;
  const std::uint32_t width = BigEndian32(bytes, 16);
  const std::uint32_t height = BigEndian32(bytes, 20);
  constexpr auto kMax = static_cast<std::uint32_t>(std::numeric_limits<int>::max());
  if (width == 0 || height == 0 || width > kMax || height > kMax) return std::nullopt;
  return ImageHeader{"png", static_cast<int>(width), static_cast<int>(height)};
}

// Walks the JPEG segments to the first frame header (SOF0-SOF15, which excludes
// DHT, JPG and DAC). Baseline and progressive encoders both write it before
// the scan data.
std::optional<ImageHeader> JpegHeader(const std::vector<std::uint8_t>& bytes) {
  if (bytes.size() < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) return std::nullopt;
  std::size_t index = 2;
  while (index + 1 < bytes.size()) {
    if (bytes[index] != 0xFF) return std::nullopt;
    const std::uint8_t marker = bytes[index + 1];
    if (marker == 0xFF) {  // A fill byte ahead of the marker.
      ++index;
      continue;
    }
    index += 2;
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    if (marker == 0xD9 || marker == 0xDA) return std::nullopt;  // No frame before the scan.
    if (index + 2 > bytes.size()) return std::nullopt;
    const std::size_t length = BigEndian16(bytes, index);
    if (length < 2) return std::nullopt;
    const bool frame = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
    if (frame) {
      // Length (2), sample precision (1), then height and width.
      if (index + 7 > bytes.size()) return std::nullopt;
      const int height = BigEndian16(bytes, index + 3);
      const int width = BigEndian16(bytes, index + 5);
      if (width == 0 || height == 0) return std::nullopt;
      return ImageHeader{"jpeg", width, height};
    }
    index += length;
  }
  return std::nullopt;
}

}  // namespace

std::optional<std::string> ParseOptions(const Json& params, BrowserScreenshotOptions* options) {
  if (const auto full_page = params.find("fullPage"); full_page != params.end()) {
    if (!full_page->is_boolean()) return "fullPage must be a boolean";
    if (full_page->get<bool>()) return "fullPage screenshots are not supported";
  }
  BrowserScreenshotOptions parsed;
  if (const auto format = params.find("format"); format != params.end()) {
    if (!format->is_string() || (*format != "png" && *format != "jpeg")) {
      return "format must be png or jpeg";
    }
    parsed.format = format->get<std::string>();
  }
  if (auto error = ReadBoundedInteger(params, "quality", 1, 100, &parsed.quality)) return error;
  if (auto error = ReadBoundedInteger(params, "maxWidth", 1, kMaxWidthLimit, &parsed.max_width)) return error;
  if (options != nullptr) *options = parsed;
  return std::nullopt;
}

std::optional<Viewport> ParseLayoutMetrics(const Json& metrics) {
  if (!metrics.is_object()) return std::nullopt;
  const auto css = metrics.find("cssVisualViewport");
  if (css == metrics.end() || !css->is_object()) return std::nullopt;
  const auto page_x = Number(*css, "pageX");
  const auto page_y = Number(*css, "pageY");
  const auto width = Number(*css, "clientWidth");
  const auto height = Number(*css, "clientHeight");
  if (!page_x || !page_y || !width || !height || *width <= 0 || *height <= 0) return std::nullopt;
  Viewport viewport{*page_x, *page_y, *width, *height, 1};
  // The deprecated `visualViewport` is the same rectangle in device pixels.
  const auto device = metrics.find("visualViewport");
  if (device != metrics.end() && device->is_object()) {
    if (const auto device_width = Number(*device, "clientWidth"); device_width && *device_width > 0) {
      viewport.device_pixel_ratio = *device_width / *width;
    }
  }
  return viewport;
}

std::optional<double> DownscaleFactor(int max_width, const Viewport& viewport) {
  const double full_width = viewport.css_width * viewport.device_pixel_ratio;
  if (max_width <= 0 || full_width <= 0 || std::round(full_width) <= max_width) return std::nullopt;
  return static_cast<double>(max_width) / full_width;
}

Json CaptureParams(const BrowserScreenshotOptions& options, const Viewport& viewport) {
  Json params = {{"format", options.format}, {"captureBeyondViewport", false}};
  if (options.format == "jpeg" && options.quality) params["quality"] = *options.quality;
  if (options.max_width) {
    if (const auto scale = DownscaleFactor(*options.max_width, viewport)) {
      params["clip"] = {{"x", viewport.page_x}, {"y", viewport.page_y},
                        {"width", viewport.css_width}, {"height", viewport.css_height},
                        {"scale", *scale}};
    }
  }
  return params;
}

std::optional<ImageHeader> ReadImageHeader(std::string_view base64) {
  const auto bytes = DecodePrefix(base64, kHeaderBytes);
  if (!bytes) return std::nullopt;
  if (auto png = PngHeader(*bytes)) return png;
  return JpegHeader(*bytes);
}

}  // namespace kelpie::desktop_screenshot
