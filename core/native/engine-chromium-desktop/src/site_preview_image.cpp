#include "site_preview_image.h"

#include <algorithm>
#include <array>

namespace kelpie::site_preview {

PixelRect PreviewCrop(int width, int height) {
  if (width <= 0 || height <= 0) return {};
  // Integer arithmetic keeps the result exact: 16:10 is width * 10 == height * 16.
  const long long wide = static_cast<long long>(width) * kPreviewHeight;
  const long long tall = static_cast<long long>(height) * kPreviewWidth;
  if (wide > tall) {
    // Wider than 16:10: keep the full height and trim the right-hand side.
    const int crop_width = static_cast<int>(tall / kPreviewHeight);
    return {0, 0, crop_width, height};
  }
  // Taller than (or exactly) 16:10: keep the full width and the top of the page.
  return {0, 0, width, static_cast<int>(wide / kPreviewWidth)};
}

PixelRect PreviewSize(const PixelRect& crop) {
  if (crop.width <= kPreviewWidth) return {0, 0, crop.width, crop.height};
  return {0, 0, kPreviewWidth, kPreviewHeight};
}

std::vector<std::uint8_t> Downscale(const std::vector<std::uint8_t>& pixels, int width, int height,
                                    const PixelRect& crop, int target_width, int target_height) {
  const bool inside = width > 0 && height > 0 && crop.x >= 0 && crop.y >= 0 && crop.width > 0 &&
                      crop.height > 0 && crop.x + crop.width <= width &&
                      crop.y + crop.height <= height;
  if (!inside || target_width <= 0 || target_height <= 0 || target_width > crop.width ||
      target_height > crop.height ||
      pixels.size() != static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U) {
    return {};
  }
  std::vector<std::uint8_t> output(static_cast<std::size_t>(target_width) * target_height * 4U);
  for (int ty = 0; ty < target_height; ++ty) {
    // Each target pixel averages the source box it covers. Bounds are computed
    // with 64-bit products so a large capture cannot overflow.
    const int y0 = crop.y + static_cast<int>(static_cast<long long>(ty) * crop.height / target_height);
    const int y1 = std::max(y0 + 1, crop.y + static_cast<int>(static_cast<long long>(ty + 1) * crop.height / target_height));
    for (int tx = 0; tx < target_width; ++tx) {
      const int x0 = crop.x + static_cast<int>(static_cast<long long>(tx) * crop.width / target_width);
      const int x1 = std::max(x0 + 1, crop.x + static_cast<int>(static_cast<long long>(tx + 1) * crop.width / target_width));
      std::array<std::uint64_t, 4> sum{};
      for (int y = y0; y < y1; ++y) {
        const std::uint8_t* row = pixels.data() + (static_cast<std::size_t>(y) * width + x0) * 4U;
        for (int x = x0; x < x1; ++x, row += 4) {
          for (int channel = 0; channel < 4; ++channel) sum[channel] += row[channel];
        }
      }
      const std::uint64_t count = static_cast<std::uint64_t>(y1 - y0) * static_cast<std::uint64_t>(x1 - x0);
      std::uint8_t* target = output.data() + (static_cast<std::size_t>(ty) * target_width + tx) * 4U;
      for (int channel = 0; channel < 4; ++channel) {
        target[channel] = static_cast<std::uint8_t>((sum[channel] + count / 2U) / count);
      }
    }
  }
  return output;
}

bool LooksBlank(const std::vector<std::uint8_t>& pixels, int width, int height) {
  if (width <= 0 || height <= 0 ||
      pixels.size() != static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U) {
    return true;
  }
  // Rec. 601 luma over the colour channels; the order (RGB or BGR) only swaps
  // the red and blue weights, which does not matter for a spread test.
  int lowest = 255;
  int highest = 0;
  for (std::size_t offset = 0; offset < pixels.size(); offset += 4) {
    const int luma = (pixels[offset] * 114 + pixels[offset + 1] * 587 + pixels[offset + 2] * 299) / 1000;
    lowest = std::min(lowest, luma);
    highest = std::max(highest, luma);
    if (highest - lowest > 12) return false;
  }
  return true;
}

std::optional<std::vector<std::uint8_t>> DecodeBase64(const std::string& encoded) {
  const auto value = [](char character) -> int {
    if (character >= 'A' && character <= 'Z') return character - 'A';
    if (character >= 'a' && character <= 'z') return character - 'a' + 26;
    if (character >= '0' && character <= '9') return character - '0' + 52;
    if (character == '+') return 62;
    if (character == '/') return 63;
    return -1;
  };
  if (encoded.size() % 4U != 0U) return std::nullopt;
  std::vector<std::uint8_t> output;
  output.reserve(encoded.size() / 4U * 3U);
  for (std::size_t index = 0; index < encoded.size(); index += 4) {
    int digits[4];
    int padding = 0;
    for (int offset = 0; offset < 4; ++offset) {
      const char character = encoded[index + offset];
      if (character == '=') {
        // Padding is only valid in the last two places of the final quantum.
        if (index + 4 != encoded.size() || offset < 2) return std::nullopt;
        digits[offset] = 0;
        ++padding;
        continue;
      }
      if (padding > 0) return std::nullopt;
      digits[offset] = value(character);
      if (digits[offset] < 0) return std::nullopt;
    }
    const std::uint32_t chunk = (static_cast<std::uint32_t>(digits[0]) << 18U) |
                                (static_cast<std::uint32_t>(digits[1]) << 12U) |
                                (static_cast<std::uint32_t>(digits[2]) << 6U) |
                                static_cast<std::uint32_t>(digits[3]);
    output.push_back(static_cast<std::uint8_t>((chunk >> 16U) & 0xFFU));
    if (padding < 2) output.push_back(static_cast<std::uint8_t>((chunk >> 8U) & 0xFFU));
    if (padding < 1) output.push_back(static_cast<std::uint8_t>(chunk & 0xFFU));
  }
  return output;
}

}  // namespace kelpie::site_preview
