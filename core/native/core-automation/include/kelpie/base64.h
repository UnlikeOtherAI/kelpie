#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace kelpie {

inline std::string Base64Encode(const std::vector<std::uint8_t>& input) {
  static constexpr char kAlphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  std::string output;
  output.reserve(((input.size() + 2U) / 3U) * 4U);

  std::size_t index = 0;
  while (index + 2U < input.size()) {
    const std::uint32_t chunk = (static_cast<std::uint32_t>(input[index]) << 16U) |
                                (static_cast<std::uint32_t>(input[index + 1U]) << 8U) |
                                static_cast<std::uint32_t>(input[index + 2U]);
    output.push_back(kAlphabet[(chunk >> 18U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 12U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 6U) & 0x3FU]);
    output.push_back(kAlphabet[chunk & 0x3FU]);
    index += 3U;
  }

  const std::size_t remaining = input.size() - index;
  if (remaining == 1U) {
    const std::uint32_t chunk = static_cast<std::uint32_t>(input[index]) << 16U;
    output.push_back(kAlphabet[(chunk >> 18U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 12U) & 0x3FU]);
    output.append("==");
  } else if (remaining == 2U) {
    const std::uint32_t chunk = (static_cast<std::uint32_t>(input[index]) << 16U) |
                                (static_cast<std::uint32_t>(input[index + 1U]) << 8U);
    output.push_back(kAlphabet[(chunk >> 18U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 12U) & 0x3FU]);
    output.push_back(kAlphabet[(chunk >> 6U) & 0x3FU]);
    output.push_back('=');
  }

  return output;
}

}  // namespace kelpie
