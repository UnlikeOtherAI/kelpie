#pragma once

#include <string>
#include <string_view>
#include <vector>

#include "kelpie/mcp_tool.h"

namespace kelpie {

struct McpCapabilities {
  StringList supported;
  StringList partial;
  StringList unsupported;
};

class McpRegistry {
 public:
  McpRegistry();
  explicit McpRegistry(std::vector<McpTool> tools);

  const std::vector<McpTool>& all_tools() const;
  std::vector<McpTool> tools_for_platform(Platform platform) const;
  std::vector<McpTool> tools_for_engine(std::string_view engine) const;
  bool is_tool_available(const std::string& name, Platform platform, std::string_view engine) const;
  McpCapabilities get_capabilities(Platform platform, std::string_view engine) const;

 private:
  std::vector<McpTool> tools_;
};

}  // namespace kelpie
