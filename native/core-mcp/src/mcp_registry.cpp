#include "kelpie/mcp_registry.h"

#include <algorithm>

namespace kelpie {

McpRegistry::McpRegistry() : McpRegistry(CreateDefaultMcpTools()) {}

McpRegistry::McpRegistry(std::vector<McpTool> tools) : tools_(std::move(tools)) {}

const std::vector<McpTool>& McpRegistry::all_tools() const {
  return tools_;
}

std::vector<McpTool> McpRegistry::tools_for_platform(Platform platform, std::string_view runtime_mode) const {
  std::vector<McpTool> matches;
  matches.reserve(tools_.size());
  for (const McpTool& tool : tools_) {
    const auto availability = AvailabilityForPlatform(tool.availability, platform, runtime_mode);
    if (SupportsPlatform(availability, platform)) {
      auto projected = tool;
      projected.availability = availability;
      matches.push_back(std::move(projected));
    }
  }
  return matches;
}

std::vector<McpTool> McpRegistry::tools_for_engine(std::string_view engine) const {
  std::vector<McpTool> matches;
  matches.reserve(tools_.size());
  for (const McpTool& tool : tools_) {
    if (SupportsEngine(tool.availability, engine)) {
      matches.push_back(tool);
    }
  }
  return matches;
}

bool McpRegistry::is_tool_available(const std::string& name, Platform platform,
                                    std::string_view engine, std::string_view runtime_mode) const {
  const auto match = std::find_if(tools_.begin(), tools_.end(),
                                  [&](const McpTool& tool) { return tool.name == name; });
  if (match == tools_.end()) {
    return false;
  }
  return SupportsRuntime(match->availability, platform, engine, runtime_mode);
}

McpCapabilities McpRegistry::get_capabilities(Platform platform, std::string_view engine, std::string_view runtime_mode) const {
  McpCapabilities capabilities;
  capabilities.supported.reserve(tools_.size());
  capabilities.partial.reserve(tools_.size());
  capabilities.unsupported.reserve(tools_.size());

  for (const McpTool& tool : tools_) {
    const auto availability = AvailabilityForPlatform(tool.availability, platform, runtime_mode);
    const bool available = SupportsRuntime(availability, platform, engine);
    if (!available) {
      capabilities.unsupported.push_back(tool.http_endpoint);
      continue;
    }
    if (HasRuntimeCaveat(availability)) {
      capabilities.partial.push_back(tool.http_endpoint);
      continue;
    }
    capabilities.supported.push_back(tool.http_endpoint);
  }

  return capabilities;
}

}  // namespace kelpie
