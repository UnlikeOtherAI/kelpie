#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace kelpie::sync {

// RFC 4648 section 5 base64url without padding, the only encoding the sync
// protocol uses for binary values.
std::string Base64UrlEncode(const std::uint8_t* data, std::size_t size);
std::string Base64UrlEncode(std::string_view bytes);

// Rejects padding, whitespace, non-alphabet characters and non-canonical
// trailing bits so one value has exactly one encoding.
std::optional<std::vector<std::uint8_t>> Base64UrlDecode(std::string_view text);

}  // namespace kelpie::sync
