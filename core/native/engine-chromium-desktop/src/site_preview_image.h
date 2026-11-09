#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// Pixel work behind a start page site preview: which part of a viewport capture
// becomes the card, how it is scaled down, and when a capture is not worth
// keeping. Pure functions with no CEF types, so both build configurations
// compile and test them; `site_preview_codec_cef.cpp` does the decoding and
// encoding around them.
namespace kelpie::site_preview {

// The stored preview: a 16:10 card at twice the largest card's CSS width, so it
// stays sharp at 200 % scaling.
inline constexpr int kPreviewWidth = 640;
inline constexpr int kPreviewHeight = 400;

struct PixelRect {
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
};

// The largest 16:10 region of a `width` x `height` capture, anchored to its
// top-left corner. Pages put their identity, usually the logo, at the top left,
// so a tall viewport loses its bottom and a wide one its right-hand side.
// Returns an empty rect for an empty capture.
PixelRect PreviewCrop(int width, int height);

// The output size for a crop: the stored preview size, or the crop itself when
// it is smaller, because upscaling only adds blur.
PixelRect PreviewSize(const PixelRect& crop);

// Box-filters `crop` of a tightly packed 4-byte-per-pixel buffer down to
// `target_width` x `target_height`. Channel order is preserved, so BGRA stays
// BGRA. Returns an empty vector when the crop does not lie inside the buffer or
// the target is larger than the crop.
std::vector<std::uint8_t> Downscale(const std::vector<std::uint8_t>& pixels, int width, int height,
                                    const PixelRect& crop, int target_width, int target_height);

// True when the image is effectively one flat colour: an unpainted surface, or a
// document that has not drawn anything yet. A real page, even a mostly white one
// with a small logo, has some spread in luminance.
bool LooksBlank(const std::vector<std::uint8_t>& pixels, int width, int height);

// Standard base64 decoding for the DevTools screenshot payload. Returns nullopt
// for anything that is not well-formed base64.
std::optional<std::vector<std::uint8_t>> DecodeBase64(const std::string& encoded);

}  // namespace kelpie::site_preview
