#pragma once

#include <optional>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

#include "kelpie/desktop_browser_control.h"

// Pure translation between a `screenshot` request and CDP's
// Page.getLayoutMetrics / Page.captureScreenshot, with no CEF dependency, so
// both engine configurations compile it and both run its tests.
//
// Chromium does the encoding and the downscaling itself: `format: "jpeg"` and
// `quality` go straight to Page.captureScreenshot, and a smaller image is a
// `clip` of the visible viewport with a `scale`. There is no second encoder
// and no decode-and-re-encode pass.
namespace kelpie::desktop_screenshot {

using Json = nlohmann::json;

inline constexpr int kMaxWidthLimit = 16384;

// Validates the request's screenshot fields. Returns the INVALID_PARAMS
// message for a request the engine cannot honour, or nothing when `options`
// has been filled in. `fullPage: false` is accepted; `fullPage: true` is not.
std::optional<std::string> ParseOptions(const Json& params, BrowserScreenshotOptions* options);

// The CSS visual viewport and the device pixels per CSS pixel, from
// Page.getLayoutMetrics.
struct Viewport {
  double page_x = 0;
  double page_y = 0;
  double css_width = 0;
  double css_height = 0;
  double device_pixel_ratio = 1;
};

std::optional<Viewport> ParseLayoutMetrics(const Json& metrics);

// The `clip.scale` that makes the image `max_width` pixels wide, or nothing
// when the full-resolution image already fits. Chromium multiplies
// `clip.scale` by the device pixel ratio, so the full image is
// css_width * device_pixel_ratio pixels wide.
std::optional<double> DownscaleFactor(int max_width, const Viewport& viewport);

// Page.captureScreenshot parameters for the visible viewport.
Json CaptureParams(const BrowserScreenshotOptions& options, const Viewport& viewport);

struct ImageHeader {
  std::string format;  // "png" or "jpeg"
  int width = 0;
  int height = 0;
};

// Reads the format and pixel size from the start of a base64 PNG (IHDR) or
// JPEG (the first SOFn marker). Only a prefix of the base64 is decoded.
std::optional<ImageHeader> ReadImageHeader(std::string_view base64);

}  // namespace kelpie::desktop_screenshot
