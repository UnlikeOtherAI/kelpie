#include "desktop_screenshot_planner.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>
#undef assert
#define assert(expression) do { if (!(expression)) std::abort(); } while (false)

#include "kelpie/base64.h"

namespace {

namespace screenshot = kelpie::desktop_screenshot;
using Json = nlohmann::json;
using Bytes = std::vector<std::uint8_t>;

void Append16(Bytes* bytes, int value) {
  bytes->push_back(static_cast<std::uint8_t>((value >> 8) & 0xFF));
  bytes->push_back(static_cast<std::uint8_t>(value & 0xFF));
}

void Append32(Bytes* bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8) bytes->push_back(static_cast<std::uint8_t>((value >> shift) & 0xFF));
}

std::string Png(std::uint32_t width, std::uint32_t height) {
  Bytes bytes = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
  Append32(&bytes, 13);
  bytes.insert(bytes.end(), {'I', 'H', 'D', 'R'});
  Append32(&bytes, width);
  Append32(&bytes, height);
  bytes.insert(bytes.end(), {8, 2, 0, 0, 0, 0, 0, 0, 0});  // depth, colour, ..., CRC
  return kelpie::Base64Encode(bytes);
}

// SOI, a JFIF APP0, a quantisation table and a Huffman table (DHT is 0xC4,
// inside the SOF range but not a frame header), then the frame header.
std::string Jpeg(std::uint8_t frame_marker, int width, int height, bool fill_byte = false) {
  Bytes bytes = {0xFF, 0xD8, 0xFF, 0xE0};
  Append16(&bytes, 16);
  bytes.insert(bytes.end(), {'J', 'F', 'I', 'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0});
  bytes.insert(bytes.end(), {0xFF, 0xDB});
  Append16(&bytes, 67);
  bytes.insert(bytes.end(), 65, 1);
  bytes.insert(bytes.end(), {0xFF, 0xC4});
  Append16(&bytes, 5);
  bytes.insert(bytes.end(), {0, 0, 0});
  if (fill_byte) bytes.push_back(0xFF);
  bytes.insert(bytes.end(), {0xFF, frame_marker});
  Append16(&bytes, 17);
  bytes.push_back(8);
  Append16(&bytes, height);
  Append16(&bytes, width);
  bytes.insert(bytes.end(), {3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1});
  bytes.insert(bytes.end(), {0xFF, 0xDA});
  return kelpie::Base64Encode(bytes);
}

void Options() {
  kelpie::BrowserScreenshotOptions options;
  assert(!screenshot::ParseOptions(Json::object(), &options));
  assert(options.format == "png" && !options.quality && !options.max_width);
  // `kelpie screenshot` always sends fullPage:false, so it has to be accepted.
  assert(!screenshot::ParseOptions({{"fullPage", false}}, &options));
  assert(!screenshot::ParseOptions({{"format", "jpeg"}, {"quality", 60}, {"maxWidth", 960}}, &options));
  assert(options.format == "jpeg" && options.quality == 60 && options.max_width == 960);
  assert(*screenshot::ParseOptions({{"fullPage", true}}, &options) == "fullPage screenshots are not supported");
  assert(*screenshot::ParseOptions({{"format", "webp"}}, &options) == "format must be png or jpeg");
  assert(screenshot::ParseOptions({{"format", 7}}, &options));
  for (const Json& quality : {Json(0), Json(101), Json(60.5), Json("60")}) {
    assert(*screenshot::ParseOptions({{"quality", quality}}, &options) == "quality must be an integer between 1 and 100");
  }
  for (const Json& width : {Json(0), Json(16385), Json(12.5), Json(-1), Json(4294967297ULL)}) {
    assert(*screenshot::ParseOptions({{"maxWidth", width}}, &options) == "maxWidth must be an integer between 1 and 16384");
  }
  // A rejected request leaves the caller's options untouched.
  assert(options.format == "jpeg" && options.max_width == 960);
}

void LayoutMetrics() {
  const Json metrics = {
      {"cssVisualViewport", {{"pageX", 0}, {"pageY", 800}, {"clientWidth", 959}, {"clientHeight", 478.5}}},
      {"visualViewport", {{"clientWidth", 1918}, {"clientHeight", 957}}},
  };
  const auto viewport = screenshot::ParseLayoutMetrics(metrics);
  assert(viewport && viewport->page_y == 800 && viewport->css_width == 959 && viewport->css_height == 478.5);
  assert(viewport->device_pixel_ratio == 2);
  Json no_device = metrics;
  no_device.erase("visualViewport");
  assert(screenshot::ParseLayoutMetrics(no_device)->device_pixel_ratio == 1);
  assert(!screenshot::ParseLayoutMetrics(Json::object()));
  Json empty = metrics;
  empty["cssVisualViewport"]["clientWidth"] = 0;
  assert(!screenshot::ParseLayoutMetrics(empty));
}

void Scale() {
  const screenshot::Viewport one{0, 0, 1921, 926, 1};
  const double half = screenshot::ClipScale(960, one);
  assert(std::abs(half - 960.0 / 1921.0) < 1e-12);
  assert(std::lround(1921 * half * one.device_pixel_ratio) == 960);
  // Chromium multiplies clip.scale by the device pixel ratio, so at 2 the
  // full image is twice the CSS width and the factor halves to match.
  const screenshot::Viewport two{0, 0, 959, 478.5, 2};
  const double scaled = screenshot::ClipScale(960, two);
  assert(std::lround(959 * scaled * two.device_pixel_ratio) == 960);
  // Never upscaled: a viewport that already fits keeps scale 1.
  assert(screenshot::ClipScale(1921, one) == 1.0);
  assert(screenshot::ClipScale(4000, one) == 1.0);
  assert(screenshot::ClipScale(1000, two) == 1000.0 / 1918.0);
}

void Capture() {
  const screenshot::Viewport viewport{12, 800, 1921, 926, 1};
  kelpie::BrowserScreenshotOptions png;
  png.quality = 60;
  const Json plain = screenshot::CaptureParams(png, viewport);
  assert(plain == (Json{{"format", "png"}, {"captureBeyondViewport", false}}));
  assert(screenshot::ImageScale(png, viewport) == 1.0);
  kelpie::BrowserScreenshotOptions jpeg;
  jpeg.format = "jpeg";
  jpeg.quality = 60;
  jpeg.max_width = 960;
  const Json small = screenshot::CaptureParams(jpeg, viewport);
  assert(small["format"] == "jpeg" && small["quality"] == 60);
  assert(small["clip"]["x"] == 12 && small["clip"]["y"] == 800);
  assert(small["clip"]["width"] == 1921 && small["clip"]["height"] == 926);
  assert(std::abs(small["clip"]["scale"].get<double>() - 960.0 / 1921.0) < 1e-12);
  assert(std::abs(screenshot::ImageScale(jpeg, viewport) - 960.0 / 1921.0) < 1e-12);
  // A maxWidth the viewport already fits is still a clip, at scale 1. A plain
  // capture includes the scrollbars (1936 px for this 1921 px viewport), so
  // skipping the clip here returned an image wider than the maxWidth asked for.
  jpeg.max_width = 1930;
  const Json fits = screenshot::CaptureParams(jpeg, viewport);
  assert(fits["clip"]["scale"] == 1.0 && fits["clip"]["width"] == 1921);
  const screenshot::Viewport retina{0, 0, 959, 478.5, 2};
  assert(screenshot::ImageScale(png, retina) == 2.0);
}

void Headers() {
  const auto png = screenshot::ReadImageHeader(Png(1918, 957));
  assert(png && png->format == "png" && png->width == 1918 && png->height == 957);
  const auto baseline = screenshot::ReadImageHeader(Jpeg(0xC0, 960, 479));
  assert(baseline && baseline->format == "jpeg" && baseline->width == 960 && baseline->height == 479);
  const auto progressive = screenshot::ReadImageHeader(Jpeg(0xC2, 640, 320, true));
  assert(progressive && progressive->format == "jpeg" && progressive->width == 640 && progressive->height == 320);
  // Truncated before the frame header, garbage, or neither format.
  const std::string whole = Jpeg(0xC0, 960, 479);
  assert(!screenshot::ReadImageHeader(whole.substr(0, 40)));
  assert(!screenshot::ReadImageHeader(Png(1918, 957).substr(0, 12)));
  assert(!screenshot::ReadImageHeader("!!!not base64!!!"));
  assert(!screenshot::ReadImageHeader("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
  assert(!screenshot::ReadImageHeader(""));
  assert(!screenshot::ReadImageHeader(Png(0, 957)));
}

}  // namespace

int main() {
  Options();
  LayoutMetrics();
  Scale();
  Capture();
  Headers();
  return 0;
}
