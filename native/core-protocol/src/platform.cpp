#include "mollotov/platform.h"

#include <string_view>

#include "mollotov/constants.h"
#include "mollotov/protocol.h"

namespace mollotov {

const char* PlatformToString(Platform platform) {
  switch (platform) {
    case Platform::kIos:
      return "ios";
    case Platform::kAndroid:
      return "android";
    case Platform::kMacos:
      return "macos";
    case Platform::kLinux:
      return "linux";
    case Platform::kWindows:
      return "windows";
  }
  return "unknown";
}

std::optional<Platform> PlatformFromString(std::string_view value) {
  if (value == "ios") {
    return Platform::kIos;
  }
  if (value == "android") {
    return Platform::kAndroid;
  }
  if (value == "macos") {
    return Platform::kMacos;
  }
  if (value == "linux") {
    return Platform::kLinux;
  }
  if (value == "windows") {
    return Platform::kWindows;
  }
  return std::nullopt;
}

}  // namespace mollotov

extern "C" {

const char* mollotov_platform_name(MollotovPlatform platform) {
  return mollotov::PlatformToString(static_cast<mollotov::Platform>(platform));
}

int32_t mollotov_default_port(void) {
  return mollotov::kDefaultPort;
}

const char* mollotov_mdns_service_type(void) {
  return mollotov::kMdnsServiceType.data();
}

const char* mollotov_api_version_prefix(void) {
  return mollotov::kApiVersionPrefix.data();
}

const char* mollotov_mcp_tool_prefix(void) {
  return mollotov::kMcpToolPrefix.data();
}

int32_t mollotov_cli_mcp_port(void) {
  return mollotov::kCliMcpPort;
}

}  // extern "C"
