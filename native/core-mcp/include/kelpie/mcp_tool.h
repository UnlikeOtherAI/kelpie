#pragma once

#include <string>
#include <string_view>
#include <vector>

#include "kelpie/platform.h"

namespace kelpie {

struct McpTool {
  std::string name;
  std::string http_endpoint;
  std::string description;
  ToolAvailability availability;
};

bool SupportsPlatform(const ToolAvailability& availability, Platform platform);
bool SupportsEngine(const ToolAvailability& availability, std::string_view engine);
ToolAvailability AvailabilityForPlatform(const ToolAvailability& availability, Platform platform,
                                        std::string_view runtime_mode = "windowed");
bool SupportsRuntime(const ToolAvailability& availability, Platform platform, std::string_view engine,
                     std::string_view runtime_mode = "windowed");
bool HasRuntimeCaveat(const ToolAvailability& availability);
std::vector<McpTool> CreateDefaultMcpTools();

}  // namespace kelpie
