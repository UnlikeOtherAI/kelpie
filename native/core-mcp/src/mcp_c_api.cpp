#include "kelpie/mcp_c_api.h"

#include <cstring>
#include <new>
#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/mcp_registry.h"

struct KelpieMcpRegistry {
  kelpie::McpRegistry registry;
};

namespace kelpie::mcp_c_api_internal {

using json = nlohmann::json;

char* CopyString(const std::string& value) {
  char* buffer = new (std::nothrow) char[value.size() + 1];
  if (buffer == nullptr) {
    return nullptr;
  }
  std::memcpy(buffer, value.c_str(), value.size() + 1);
  return buffer;
}

json AvailabilityToJson(const kelpie::ToolAvailability& availability) {
  json payload = {
      {"platforms", json::array()},
      {"engines", availability.engines},
      {"requires_ui", availability.requires_ui},
      {"allowed_headless", availability.allowed_headless},
      {"required_capabilities", availability.required_capabilities},
  };
  for (const kelpie::Platform platform : availability.platforms) {
    payload["platforms"].push_back(kelpie::PlatformToString(platform));
  }
  return payload;
}

bool ParsePlatform(int32_t raw_platform, kelpie::Platform* platform) {
  if (platform == nullptr) {
    return false;
  }
  switch (raw_platform) {
    case KELPIE_PLATFORM_IOS:
    case KELPIE_PLATFORM_ANDROID:
    case KELPIE_PLATFORM_MACOS:
    case KELPIE_PLATFORM_LINUX:
    case KELPIE_PLATFORM_WINDOWS:
      *platform = static_cast<kelpie::Platform>(raw_platform);
      return true;
    default:
      return false;
  }
}

const char* SafeCString(const char* value) {
  return value == nullptr ? "" : value;
}

}  // namespace kelpie::mcp_c_api_internal

extern "C" {

KelpieMcpRegistryRef kelpie_mcp_registry_create(void) {
  try {
    return new KelpieMcpRegistry();
  } catch (...) {
    return nullptr;
  }
}

char* kelpie_mcp_registry_tools_for_platform(KelpieMcpRegistryRef registry, int32_t platform) {
  if (registry == nullptr) {
    return nullptr;
  }
  kelpie::Platform parsed_platform;
  if (!kelpie::mcp_c_api_internal::ParsePlatform(platform, &parsed_platform)) {
    return nullptr;
  }

  try {
    nlohmann::json payload = nlohmann::json::array();
    for (const kelpie::McpTool& tool : registry->registry.tools_for_platform(parsed_platform)) {
      payload.push_back({
          {"name", tool.name},
          {"http_endpoint", tool.http_endpoint},
          {"description", tool.description},
          {"availability", kelpie::mcp_c_api_internal::AvailabilityToJson(tool.availability)},
      });
    }
    return kelpie::mcp_c_api_internal::CopyString(payload.dump());
  } catch (...) {
    return nullptr;
  }
}

int32_t kelpie_mcp_registry_is_available(KelpieMcpRegistryRef registry,
                                           const char* name,
                                           int32_t platform,
                                           const char* engine) {
  if (registry == nullptr) {
    return 0;
  }
  kelpie::Platform parsed_platform;
  if (!kelpie::mcp_c_api_internal::ParsePlatform(platform, &parsed_platform)) {
    return 0;
  }

  try {
    return registry->registry.is_tool_available(
               kelpie::mcp_c_api_internal::SafeCString(name), parsed_platform,
               kelpie::mcp_c_api_internal::SafeCString(engine))
               ? 1
               : 0;
  } catch (...) {
    return 0;
  }
}

char* kelpie_mcp_registry_get_capabilities(KelpieMcpRegistryRef registry,
                                             int32_t platform,
                                             const char* engine) {
  if (registry == nullptr) {
    return nullptr;
  }
  kelpie::Platform parsed_platform;
  if (!kelpie::mcp_c_api_internal::ParsePlatform(platform, &parsed_platform)) {
    return nullptr;
  }

  try {
    const kelpie::McpCapabilities capabilities =
        registry->registry.get_capabilities(parsed_platform,
                                            kelpie::mcp_c_api_internal::SafeCString(engine));
    const nlohmann::json payload = {
        {"platform", kelpie::PlatformToString(parsed_platform)},
        {"engine", kelpie::mcp_c_api_internal::SafeCString(engine)},
        {"supported", capabilities.supported},
        {"partial", capabilities.partial},
        {"unsupported", capabilities.unsupported},
    };
    return kelpie::mcp_c_api_internal::CopyString(payload.dump());
  } catch (...) {
    return nullptr;
  }
}

void kelpie_mcp_registry_destroy(KelpieMcpRegistryRef registry) {
  delete registry;
}

void kelpie_mcp_free_string(char* value) {
  delete[] value;
}

}  // extern "C"
