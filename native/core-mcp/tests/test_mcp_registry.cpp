#include "mollotov/mcp_c_api.h"
#include "mollotov/mcp_registry.h"
#include "mollotov/platform.h"

#include <algorithm>
#include <cassert>
#include <iostream>

#include <nlohmann/json.hpp>

namespace {

using json = nlohmann::json;

bool ContainsTool(const std::vector<mollotov::McpTool>& tools, const std::string& name) {
  return std::any_of(tools.begin(), tools.end(),
                     [&](const mollotov::McpTool& tool) { return tool.name == name; });
}

bool ContainsString(const mollotov::StringList& values, const std::string& expected) {
  return std::find(values.begin(), values.end(), expected) != values.end();
}

void TestAlternativeEngineRegions() {
  assert(mollotov::kAlternativeEngineRegions.size() == 29);
  assert(mollotov::IsAlternativeEngineRegion("gb"));
  assert(mollotov::IsAlternativeEngineRegion("JP"));
  assert(!mollotov::IsAlternativeEngineRegion("US"));
}

void TestRegistryFiltering() {
  const mollotov::McpRegistry registry;
  assert(registry.all_tools().size() == 90);

  const auto ios_tools = registry.tools_for_platform(mollotov::Platform::kIos);
  const auto android_tools = registry.tools_for_platform(mollotov::Platform::kAndroid);
  const auto macos_tools = registry.tools_for_platform(mollotov::Platform::kMacos);
  const auto windows_tools = registry.tools_for_platform(mollotov::Platform::kWindows);
  const auto webkit_tools = registry.tools_for_engine("webkit");
  const auto chromium_tools = registry.tools_for_engine("chromium");

  assert(ios_tools.size() == 90);
  assert(android_tools.size() == 89);
  assert(macos_tools.size() == 84);
  assert(windows_tools.size() == 83);
  assert(webkit_tools.size() == 90);
  assert(chromium_tools.size() == 89);

  assert(ContainsTool(ios_tools, "mollotov_safari_auth"));
  assert(!ContainsTool(android_tools, "mollotov_safari_auth"));
  assert(!ContainsTool(macos_tools, "mollotov_show_keyboard"));
  assert(!ContainsTool(windows_tools, "mollotov_set_orientation"));
}

void TestAvailabilityChecks() {
  const mollotov::McpRegistry registry;
  assert(registry.is_tool_available("mollotov_safari_auth", mollotov::Platform::kIos, "webkit"));
  assert(!registry.is_tool_available("mollotov_safari_auth", mollotov::Platform::kIos, "chromium"));
  assert(!registry.is_tool_available("mollotov_safari_auth", mollotov::Platform::kAndroid, "webkit"));
  assert(registry.is_tool_available("mollotov_set_renderer", mollotov::Platform::kWindows, "gecko"));
  assert(registry.is_tool_available("mollotov_show_keyboard", mollotov::Platform::kAndroid, "chromium"));
  assert(!registry.is_tool_available("mollotov_show_keyboard", mollotov::Platform::kMacos, "webkit"));
}

void TestCapabilitiesClassification() {
  const mollotov::McpRegistry registry;

  const auto ios_webkit = registry.get_capabilities(mollotov::Platform::kIos, "webkit");
  assert(ContainsString(ios_webkit.supported, "navigate"));
  assert(ContainsString(ios_webkit.partial, "show-keyboard"));
  assert(ContainsString(ios_webkit.partial, "safari-auth"));
  assert(ContainsString(ios_webkit.partial, "set-renderer"));
  assert(!ContainsString(ios_webkit.unsupported, "safari-auth"));

  const auto macos_chromium = registry.get_capabilities(mollotov::Platform::kMacos, "chromium");
  assert(ContainsString(macos_chromium.supported, "navigate"));
  assert(ContainsString(macos_chromium.partial, "set-renderer"));
  assert(ContainsString(macos_chromium.unsupported, "safari-auth"));
  assert(ContainsString(macos_chromium.unsupported, "show-keyboard"));
}

void TestCApi() {
  MollotovMcpRegistryRef registry = mollotov_mcp_registry_create();
  assert(registry != nullptr);

  char* ios_tools_json = mollotov_mcp_registry_tools_for_platform(registry, MOLLOTOV_PLATFORM_IOS);
  assert(ios_tools_json != nullptr);
  const json ios_tools = json::parse(ios_tools_json);
  mollotov_mcp_free_string(ios_tools_json);
  assert(ios_tools.size() == 90);
  assert(ios_tools[0].contains("availability"));

  assert(mollotov_mcp_registry_is_available(registry, "mollotov_safari_auth", MOLLOTOV_PLATFORM_IOS,
                                            "webkit") == 1);
  assert(mollotov_mcp_registry_is_available(registry, "mollotov_safari_auth", MOLLOTOV_PLATFORM_IOS,
                                            "chromium") == 0);

  char* capabilities_json =
      mollotov_mcp_registry_get_capabilities(registry, MOLLOTOV_PLATFORM_ANDROID, "chromium");
  assert(capabilities_json != nullptr);
  const json capabilities = json::parse(capabilities_json);
  mollotov_mcp_free_string(capabilities_json);

  assert(capabilities["platform"] == "android");
  assert(std::find(capabilities["supported"].begin(), capabilities["supported"].end(), "navigate") !=
         capabilities["supported"].end());
  assert(std::find(capabilities["partial"].begin(), capabilities["partial"].end(), "show-keyboard") !=
         capabilities["partial"].end());
  assert(std::find(capabilities["unsupported"].begin(), capabilities["unsupported"].end(),
                   "safari-auth") != capabilities["unsupported"].end());

  mollotov_mcp_registry_destroy(registry);
}

}  // namespace

int main() {
  try {
    TestAlternativeEngineRegions();
    TestRegistryFiltering();
    TestAvailabilityChecks();
    TestCapabilitiesClassification();
    TestCApi();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
