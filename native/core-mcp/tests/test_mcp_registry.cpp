#include "kelpie/mcp_c_api.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/platform.h"

#include <algorithm>
#include <cassert>
#include <cstdlib>
#include <iostream>

#include <nlohmann/json.hpp>

#undef assert
#define assert(expression) do { if (!(expression)) std::abort(); } while (false)

namespace {

using json = nlohmann::json;

bool ContainsTool(const std::vector<kelpie::McpTool>& tools, const std::string& name) {
  return std::any_of(tools.begin(), tools.end(),
                     [&](const kelpie::McpTool& tool) { return tool.name == name; });
}

bool ContainsString(const kelpie::StringList& values, const std::string& expected) {
  return std::find(values.begin(), values.end(), expected) != values.end();
}

void TestAlternativeEngineRegions() {
  assert(kelpie::kAlternativeEngineRegions.size() == 29);
  assert(kelpie::IsAlternativeEngineRegion("gb"));
  assert(kelpie::IsAlternativeEngineRegion("JP"));
  assert(!kelpie::IsAlternativeEngineRegion("US"));
}

void TestRegistryFiltering() {
  const kelpie::McpRegistry registry;
  const auto all_tools = registry.all_tools();
  assert(!all_tools.empty());
  for (const auto& tool : all_tools) {
    assert(!tool.name.empty());
    assert(!tool.http_endpoint.empty());
  }

  const auto ios_tools = registry.tools_for_platform(kelpie::Platform::kIos);
  const auto android_tools = registry.tools_for_platform(kelpie::Platform::kAndroid);
  const auto macos_tools = registry.tools_for_platform(kelpie::Platform::kMacos);
  const auto windows_tools = registry.tools_for_platform(kelpie::Platform::kWindows);
  const auto linux_tools = registry.tools_for_platform(kelpie::Platform::kLinux);
  assert(linux_tools.size() == 114);
  for (const auto& tool : linux_tools) assert(ContainsTool(windows_tools, tool.name));
  for (const auto* name : {"kelpie_play_script", "kelpie_abort_script", "kelpie_get_script_status", "kelpie_get_script_artifact"}) {
    assert(ContainsTool(windows_tools, name));
    assert(!ContainsTool(linux_tools, name));
    assert(ContainsTool(ios_tools, name));
    assert(registry.is_tool_available(name, kelpie::Platform::kIos, "webkit"));
    assert(!registry.is_tool_available(name, kelpie::Platform::kIos, "chromium"));
    assert(!registry.is_tool_available(name, kelpie::Platform::kIos, "gecko"));
    assert(ContainsTool(android_tools, name));
    assert(registry.is_tool_available(name, kelpie::Platform::kAndroid, "chromium"));
    assert(!registry.is_tool_available(name, kelpie::Platform::kAndroid, "webkit"));
    assert(!registry.is_tool_available(name, kelpie::Platform::kAndroid, "gecko"));
    assert(!ContainsTool(macos_tools, name));
    assert(registry.is_tool_available(name, kelpie::Platform::kWindows, "chromium"));
    assert(!registry.is_tool_available(name, kelpie::Platform::kWindows, "webkit"));
    assert(!registry.is_tool_available(name, kelpie::Platform::kWindows, "gecko"));
  }
  const auto play = std::find_if(windows_tools.begin(), windows_tools.end(), [](const auto& tool) { return tool.name == "kelpie_play_script"; });
  assert(play != windows_tools.end());
  assert(play->availability.requires_ui);
  assert(!play->availability.allowed_headless);
  for (const auto& tool : ios_tools) if (tool.http_endpoint == "play-script" ||
      tool.http_endpoint == "abort-script" || tool.http_endpoint == "get-script-status" ||
      tool.http_endpoint == "get-script-artifact") {
    assert(tool.availability.platforms == std::vector<kelpie::Platform>{kelpie::Platform::kIos});
    assert(tool.availability.engines == kelpie::StringList{"webkit"});
    assert(tool.availability.requires_ui); assert(!tool.availability.allowed_headless);
  }
  for (const auto& tool : android_tools) if (tool.http_endpoint == "play-script" ||
      tool.http_endpoint == "abort-script" || tool.http_endpoint == "get-script-status" ||
      tool.http_endpoint == "get-script-artifact") {
    assert(tool.availability.platforms == std::vector<kelpie::Platform>{kelpie::Platform::kAndroid});
    assert(tool.availability.engines == kelpie::StringList{"chromium"});
    assert(tool.availability.requires_ui); assert(!tool.availability.allowed_headless);
  }
  const auto webkit_tools = registry.tools_for_engine("webkit");
  const auto chromium_tools = registry.tools_for_engine("chromium");

  // Exact counts: a tool that quietly appears on or disappears from a platform
  // is the regression this guards, and `<= all_tools.size()` cannot see it.
  // Update these deliberately when the catalogue changes.
  assert(all_tools.size() == 128);
  assert(ios_tools.size() == 125);
  assert(android_tools.size() == 125);
  assert(macos_tools.size() == 118);
  assert(windows_tools.size() == 118);
  assert(webkit_tools.size() == 128);
  assert(chromium_tools.size() == 128);

  for (const auto* name : {"kelpie_bookmarks_create_folder", "kelpie_bookmarks_update", "kelpie_bookmarks_move"}) {
    assert(ContainsTool(ios_tools, name));
    assert(ContainsTool(android_tools, name));
    assert(ContainsTool(macos_tools, name));
    assert(!ContainsTool(windows_tools, name));
    assert(!ContainsTool(linux_tools, name));
  }

  // All platforms expose named storage; unsupported mobile engines fail closed.
  assert(ContainsTool(windows_tools, "kelpie_get_partitions"));
  assert(ContainsTool(macos_tools, "kelpie_delete_partition"));
  assert(ContainsTool(ios_tools, "kelpie_get_partitions"));
  assert(ContainsTool(android_tools, "kelpie_delete_partition"));

  // Windows-only in the shared catalogue, so Windows-only here too.
  assert(ContainsTool(windows_tools, "kelpie_close_browser"));
  assert(!ContainsTool(ios_tools, "kelpie_close_browser"));
  assert(!ContainsTool(android_tools, "kelpie_close_browser"));
  assert(!ContainsTool(macos_tools, "kelpie_close_browser"));
  assert(ContainsTool(windows_tools, "kelpie_press_key"));
  assert(!ContainsTool(ios_tools, "kelpie_press_key"));
  assert(!ContainsTool(android_tools, "kelpie_press_key"));
  assert(!ContainsTool(macos_tools, "kelpie_press_key"));

  assert(!ContainsTool(ios_tools, "kelpie_safari_auth"));
  assert(!ContainsTool(macos_tools, "kelpie_safari_auth"));
  assert(ContainsTool(macos_tools, "kelpie_set_orientation"));
  assert(!ContainsTool(macos_tools, "kelpie_show_keyboard"));
  assert(!ContainsTool(windows_tools, "kelpie_set_orientation"));
}

void TestAvailabilityChecks() {
  const kelpie::McpRegistry registry;
  assert(!registry.is_tool_available("kelpie_safari_auth", kelpie::Platform::kIos, "webkit"));
  assert(registry.is_tool_available("kelpie_set_renderer", kelpie::Platform::kWindows, "gecko"));
  assert(registry.is_tool_available("kelpie_set_orientation", kelpie::Platform::kMacos, "webkit"));
  assert(registry.is_tool_available("kelpie_show_keyboard", kelpie::Platform::kAndroid, "chromium"));
  assert(!registry.is_tool_available("kelpie_show_keyboard", kelpie::Platform::kMacos, "webkit"));
}

void TestCapabilitiesClassification() {
  const kelpie::McpRegistry registry;

  const auto ios_webkit = registry.get_capabilities(kelpie::Platform::kIos, "webkit");
  assert(ContainsString(ios_webkit.supported, "navigate"));
  assert(ContainsString(ios_webkit.partial, "show-keyboard"));
  for (const auto* endpoint : {"play-script", "abort-script", "get-script-status", "get-script-artifact"})
    assert(ContainsString(ios_webkit.partial, endpoint));
  assert(ContainsString(ios_webkit.partial, "set-renderer"));
  assert(!ContainsString(ios_webkit.unsupported, "show-keyboard"));

  const auto windows_chromium = registry.get_capabilities(kelpie::Platform::kWindows, "chromium");
  assert(ContainsString(windows_chromium.partial, "play-script"));
  assert(!ContainsString(windows_chromium.supported, "play-script"));
  const auto macos_chromium = registry.get_capabilities(kelpie::Platform::kMacos, "chromium");
  assert(ContainsString(macos_chromium.supported, "navigate"));
  assert(ContainsString(macos_chromium.partial, "set-renderer"));
  assert(ContainsString(macos_chromium.unsupported, "show-keyboard"));
}

void TestCApi() {
  KelpieMcpRegistryRef registry = kelpie_mcp_registry_create();
  assert(registry != nullptr);

  char* ios_tools_json = kelpie_mcp_registry_tools_for_platform(registry, KELPIE_PLATFORM_IOS);
  assert(ios_tools_json != nullptr);
  const json ios_tools = json::parse(ios_tools_json);
  kelpie_mcp_free_string(ios_tools_json);
  assert(ios_tools.size() == kelpie::McpRegistry().tools_for_platform(kelpie::Platform::kIos).size());
  assert(ios_tools[0].contains("inputSchema"));
  assert(ios_tools[0].contains("mutates"));
  assert(ios_tools[0]["method"] == ios_tools[0]["http_endpoint"]);
  assert(ios_tools[0].contains("availability"));
  for (const auto& tool : ios_tools) if (tool["method"] == "play-script" ||
      tool["method"] == "abort-script" || tool["method"] == "get-script-status" ||
      tool["method"] == "get-script-artifact") {
    assert(tool["availability"]["engines"] == json::array({"webkit"}));
    assert(tool["availability"]["platforms"] == json::array({"ios"}));
    assert(tool["availability"]["requires_ui"] == true);
    assert(tool["availability"]["allowed_headless"] == false);
    assert(tool["mutates"] == (tool["method"] == "play-script" || tool["method"] == "abort-script"));
  }

  assert(kelpie_mcp_registry_is_available(registry, "kelpie_show_keyboard", KELPIE_PLATFORM_IOS,
                                            "webkit") == 1);
  assert(kelpie_mcp_registry_is_available(registry, "kelpie_show_keyboard", KELPIE_PLATFORM_MACOS,
                                            "webkit") == 0);

  char* capabilities_json =
      kelpie_mcp_registry_get_capabilities(registry, KELPIE_PLATFORM_ANDROID, "chromium");
  assert(capabilities_json != nullptr);
  const json capabilities = json::parse(capabilities_json);
  kelpie_mcp_free_string(capabilities_json);

  assert(capabilities["platform"] == "android");
  assert(std::find(capabilities["supported"].begin(), capabilities["supported"].end(), "navigate") !=
         capabilities["supported"].end());
  assert(std::find(capabilities["partial"].begin(), capabilities["partial"].end(), "show-keyboard") !=
         capabilities["partial"].end());
  assert(std::find(capabilities["unsupported"].begin(), capabilities["unsupported"].end(),
                   "safari-auth") == capabilities["unsupported"].end());

  kelpie_mcp_registry_destroy(registry);
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
