#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "kelpie/types.h"

namespace kelpie {

enum class Platform {
  kIos = 0,
  kAndroid,
  kMacos,
  kLinux,
  kWindows,
};

struct ToolAvailability {
  std::vector<Platform> platforms;
  std::vector<std::string> engines;
  bool requires_ui = false;
  bool allowed_headless = false;
  std::vector<std::string> required_capabilities;
};

const char* PlatformToString(Platform platform);
std::optional<Platform> PlatformFromString(std::string_view value);
bool IsAlternativeEngineRegion(std::string_view value);

extern const StringSet kAlternativeEngineRegions;

}  // namespace kelpie
