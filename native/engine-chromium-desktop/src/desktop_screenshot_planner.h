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

// The `clip.scale` for a `maxWidth` capture: the one that makes the visible
// viewport `max_width` pixels wide, capped at 1 so an image is never scaled
// up. Chromium multiplies `clip.scale` by the device pixel ratio, so at scale
// 1 the clip is css_width * device_pixel_ratio pixels wide.
double ClipScale(int max_width, const Viewport& viewport);

// Page.captureScreenshot parameters. A `maxWidth` capture is always a clip of
// the CSS visual viewport: a plain capture also includes the page's
// scrollbars, which the viewport metrics leave out, so its width cannot be
// known in advance -- a 1921 px viewport came back as a 1936 px image.
Json CaptureParams(const BrowserScreenshotOptions& options, const Viewport& viewport);

// Image pixels per CSS pixel for a capture made with CaptureParams, on both
// axes. The image's origin is the visible viewport's top-left corner.
double ImageScale(const BrowserScreenshotOptions& options, const Viewport& viewport);

struct ImageHeader {
  std::string format;  // "png" or "jpeg"
  int width = 0;
  int height = 0;
};

// Reads the format and pixel size from the start of a base64 PNG (IHDR) or
// JPEG (the first SOFn marker). Only a prefix of the base64 is decoded.
std::optional<ImageHeader> ReadImageHeader(std::string_view base64);

}  // namespace kelpie::desktop_screenshot
