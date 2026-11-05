#pragma once
#include <cmath>
#include <cstddef>

namespace kelpie_mac_capture {
constexpr double kMaximumSourceDimension = 8192;
constexpr double kMaximumSourcePixels = 8 * 1024 * 1024;
// PNG permits up to eight bytes/pixel (RGBA16). Reserve four MiB for framing/deflate overhead.
// Admission bounds the renderer raster before the protocol command; this is not the artifact cap.
constexpr std::size_t kMaximumPngBytes = 68 * 1024 * 1024;
constexpr std::size_t kMaximumBase64Characters = ((kMaximumPngBytes + 2) / 3) * 4;

inline bool AdmitsSource(double width, double height) {
    return std::isfinite(width) && std::isfinite(height) && width >= 2 && height >= 2 &&
           std::ceil(width) <= kMaximumSourceDimension && std::ceil(height) <= kMaximumSourceDimension &&
           std::ceil(width) * std::ceil(height) <= kMaximumSourcePixels;
}
}  // namespace kelpie_mac_capture
