#pragma once

#include <cstdint>
#include <string_view>

namespace mollotov {

inline constexpr std::int32_t kDefaultPort = 8420;
inline constexpr std::string_view kMdnsServiceType = "_mollotov._tcp";
inline constexpr std::string_view kApiVersionPrefix = "/v1/";
inline constexpr std::string_view kMcpToolPrefix = "mollotov_";
inline constexpr std::int32_t kCliMcpPort = 8421;

}  // namespace mollotov
