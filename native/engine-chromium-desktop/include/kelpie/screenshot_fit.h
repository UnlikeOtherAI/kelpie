#pragma once

#include <cstddef>
#include <functional>
#include <optional>

namespace kelpie {

// Account connection jobs keep a screenshot's base64 payload inside the
// connect ledger's terminal-output budget (768 KiB serialized) with headroom
// for the surrounding job envelope.
inline constexpr std::size_t kAccountScreenshotBase64Limit = 640 * 1024;

enum class ScreenshotFit { kFits, kFailed, kTooLarge };

// Takes one capture. `jpeg_quality` is empty for the caller's own first
// encoding and set for each JPEG retry. Returns the base64 length, or nullopt
// when the capture or any of its fences failed.
using ScreenshotCapture = std::function<std::optional<std::size_t>(std::optional<int> jpeg_quality)>;

// Captures once, then retakes JPEG at quality 80, 60 and 40, stopping at the
// first image whose base64 payload fits `limit`.
inline ScreenshotFit FitScreenshot(std::size_t limit, const ScreenshotCapture& capture) {
  static constexpr int kQualities[] = {80, 60, 40};
  auto size = capture(std::nullopt);
  for (const int quality : kQualities) {
    if (!size) return ScreenshotFit::kFailed;
    if (*size <= limit) return ScreenshotFit::kFits;
    size = capture(quality);
  }
  if (!size) return ScreenshotFit::kFailed;
  return *size <= limit ? ScreenshotFit::kFits : ScreenshotFit::kTooLarge;
}

}  // namespace kelpie
