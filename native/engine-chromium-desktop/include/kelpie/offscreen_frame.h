#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace kelpie {
// Pixels and dimensions travel together. Consumers must never infer the stride
// from a widget allocation that may have changed since CEF painted this frame.
struct OffscreenFrame {
  std::string tab_id;
  std::uint64_t generation = 0;
  int width = 0, height = 0;
  std::vector<std::uint8_t> pixels;
  bool valid() const {
    return width > 0 && height > 0 && width <= 16384 && height <= 16384 &&
        pixels.size() == static_cast<std::size_t>(width) * height * 4;
  }
};
}  // namespace kelpie
