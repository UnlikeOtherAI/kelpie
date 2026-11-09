#include "base64url.h"

namespace kelpie::sync {
namespace {

constexpr char kAlphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

int DecodeChar(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '-') return 62;
  if (c == '_') return 63;
  return -1;
}

}  // namespace

std::string Base64UrlEncode(const std::uint8_t* data, std::size_t size) {
  std::string out;
  out.reserve((size * 4 + 2) / 3);
  std::size_t i = 0;
  for (; i + 3 <= size; i += 3) {
    const std::uint32_t n = (static_cast<std::uint32_t>(data[i]) << 16) |
                            (static_cast<std::uint32_t>(data[i + 1]) << 8) | data[i + 2];
    out.push_back(kAlphabet[(n >> 18) & 63]);
    out.push_back(kAlphabet[(n >> 12) & 63]);
    out.push_back(kAlphabet[(n >> 6) & 63]);
    out.push_back(kAlphabet[n & 63]);
  }
  const std::size_t rest = size - i;
  if (rest == 1) {
    const std::uint32_t n = static_cast<std::uint32_t>(data[i]) << 16;
    out.push_back(kAlphabet[(n >> 18) & 63]);
    out.push_back(kAlphabet[(n >> 12) & 63]);
  } else if (rest == 2) {
    const std::uint32_t n = (static_cast<std::uint32_t>(data[i]) << 16) |
                            (static_cast<std::uint32_t>(data[i + 1]) << 8);
    out.push_back(kAlphabet[(n >> 18) & 63]);
    out.push_back(kAlphabet[(n >> 12) & 63]);
    out.push_back(kAlphabet[(n >> 6) & 63]);
  }
  return out;
}

std::string Base64UrlEncode(std::string_view bytes) {
  return Base64UrlEncode(reinterpret_cast<const std::uint8_t*>(bytes.data()), bytes.size());
}

std::optional<std::vector<std::uint8_t>> Base64UrlDecode(std::string_view text) {
  if (text.size() % 4 == 1) return std::nullopt;
  std::vector<std::uint8_t> out;
  out.reserve(text.size() * 3 / 4);
  std::uint32_t accumulator = 0;
  int bits = 0;
  for (const char c : text) {
    const int value = DecodeChar(c);
    if (value < 0) return std::nullopt;
    accumulator = (accumulator << 6) | static_cast<std::uint32_t>(value);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push_back(static_cast<std::uint8_t>((accumulator >> bits) & 0xff));
    }
  }
  // Leftover bits must be zero, otherwise two strings would decode to the same bytes.
  if (bits > 0 && (accumulator & ((1u << bits) - 1)) != 0) return std::nullopt;
  return out;
}

}  // namespace kelpie::sync
