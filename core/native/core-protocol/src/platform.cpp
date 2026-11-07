#include "kelpie/platform.h"

#include <algorithm>
#include <cctype>
#include <string_view>

#include "kelpie/constants.h"
#include "kelpie/protocol.h"

namespace kelpie {

const StringSet kAlternativeEngineRegions = {
    "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GB",
    "GR", "HR", "HU", "IE", "IT", "JP", "LT", "LU", "LV", "MT", "NL", "PL",
    "PT", "RO", "SE", "SI", "SK",
};

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

bool IsAlternativeEngineRegion(std::string_view value) {
  std::string normalized(value);
  std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                 [](unsigned char character) { return static_cast<char>(std::toupper(character)); });
  return kAlternativeEngineRegions.find(normalized) != kAlternativeEngineRegions.end();
}

}  // namespace kelpie

extern "C" {

const char* kelpie_platform_name(KelpiePlatform platform) {
  return kelpie::PlatformToString(static_cast<kelpie::Platform>(platform));
}

int32_t kelpie_default_port(void) {
  return kelpie::kDefaultPort;
}

const char* kelpie_mdns_service_type(void) {
  return kelpie::kMdnsServiceType.data();
}

const char* kelpie_api_version_prefix(void) {
  return kelpie::kApiVersionPrefix.data();
}

const char* kelpie_mcp_tool_prefix(void) {
  return kelpie::kMcpToolPrefix.data();
}

int32_t kelpie_cli_mcp_port(void) {
  return kelpie::kCliMcpPort;
}

}  // extern "C"
