#include "mollotov/mcp_c_api.h"

#include <cstring>
#include <new>
#include <string>

#include <nlohmann/json.hpp>

#include "mollotov/mcp_registry.h"

struct MollotovMcpRegistry {
  mollotov::McpRegistry registry;
};

namespace mollotov::mcp_c_api_internal {

using json = nlohmann::json;

char* CopyString(const std::string& value) {
  char* buffer = new (std::nothrow) char[value.size() + 1];
  if (buffer == nullptr) {
    return nullptr;
  }
  std::memcpy(buffer, value.c_str(), value.size() + 1);
  return buffer;
}

json AvailabilityToJson(const mollotov::ToolAvailability& availability) {
  json payload = {
      {"platforms", json::array()},
      {"engines", availability.engines},
      {"requires_ui", availability.requires_ui},
      {"allowed_headless", availability.allowed_headless},
      {"required_capabilities", availability.required_capabilities},
  };
  for (const mollotov::Platform platform : availability.platforms) {
    payload["platforms"].push_back(mollotov::PlatformToString(platform));
  }
  return payload;
}

bool ParsePlatform(int32_t raw_platform, mollotov::Platform* platform) {
  if (platform == nullptr) {
    return false;
  }
  switch (raw_platform) {
    case MOLLOTOV_PLATFORM_IOS:
    case MOLLOTOV_PLATFORM_ANDROID:
    case MOLLOTOV_PLATFORM_MACOS:
    case MOLLOTOV_PLATFORM_LINUX:
    case MOLLOTOV_PLATFORM_WINDOWS:
      *platform = static_cast<mollotov::Platform>(raw_platform);
      return true;
    default:
      return false;
  }
}

const char* SafeCString(const char* value) {
  return value == nullptr ? "" : value;
}

}  // namespace mollotov::mcp_c_api_internal

extern "C" {

MollotovMcpRegistryRef mollotov_mcp_registry_create(void) {
  try {
    return new MollotovMcpRegistry();
  } catch (...) {
    return nullptr;
  }
}

char* mollotov_mcp_registry_tools_for_platform(MollotovMcpRegistryRef registry, int32_t platform) {
  if (registry == nullptr) {
    return nullptr;
  }
  mollotov::Platform parsed_platform;
  if (!mollotov::mcp_c_api_internal::ParsePlatform(platform, &parsed_platform)) {
    return nullptr;
  }

  try {
    nlohmann::json payload = nlohmann::json::array();
    for (const mollotov::McpTool& tool : registry->registry.tools_for_platform(parsed_platform)) {
      payload.push_back({
          {"name", tool.name},
          {"http_endpoint", tool.http_endpoint},
          {"description", tool.description},
          {"availability", mollotov::mcp_c_api_internal::AvailabilityToJson(tool.availability)},
      });
    }
    return mollotov::mcp_c_api_internal::CopyString(payload.dump());
  } catch (...) {
    return nullptr;
  }
}

int32_t mollotov_mcp_registry_is_available(MollotovMcpRegistryRef registry,
                                           const char* name,
                                           int32_t platform,
                                           const char* engine) {
  if (registry == nullptr) {
    return 0;
  }
  mollotov::Platform parsed_platform;
  if (!mollotov::mcp_c_api_internal::ParsePlatform(platform, &parsed_platform)) {
    return 0;
  }

  try {
    return registry->registry.is_tool_available(
               mollotov::mcp_c_api_internal::SafeCString(name), parsed_platform,
               mollotov::mcp_c_api_internal::SafeCString(engine))
               ? 1
               : 0;
  } catch (...) {
    return 0;
  }
}

char* mollotov_mcp_registry_get_capabilities(MollotovMcpRegistryRef registry,
                                             int32_t platform,
                                             const char* engine) {
  if (registry == nullptr) {
    return nullptr;
  }
  mollotov::Platform parsed_platform;
  if (!mollotov::mcp_c_api_internal::ParsePlatform(platform, &parsed_platform)) {
    return nullptr;
  }

  try {
    const mollotov::McpCapabilities capabilities =
        registry->registry.get_capabilities(parsed_platform,
                                            mollotov::mcp_c_api_internal::SafeCString(engine));
    const nlohmann::json payload = {
        {"platform", mollotov::PlatformToString(parsed_platform)},
        {"engine", mollotov::mcp_c_api_internal::SafeCString(engine)},
        {"supported", capabilities.supported},
        {"partial", capabilities.partial},
        {"unsupported", capabilities.unsupported},
    };
    return mollotov::mcp_c_api_internal::CopyString(payload.dump());
  } catch (...) {
    return nullptr;
  }
}

void mollotov_mcp_registry_destroy(MollotovMcpRegistryRef registry) {
  delete registry;
}

void mollotov_mcp_free_string(char* value) {
  delete[] value;
}

}  // extern "C"
