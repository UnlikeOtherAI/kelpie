#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum KelpiePlatform {
  KELPIE_PLATFORM_IOS = 0,
  KELPIE_PLATFORM_ANDROID = 1,
  KELPIE_PLATFORM_MACOS = 2,
  KELPIE_PLATFORM_LINUX = 3,
  KELPIE_PLATFORM_WINDOWS = 4,
} KelpiePlatform;

typedef enum KelpieErrorCode {
  KELPIE_ERROR_ELEMENT_NOT_FOUND = 0,
  KELPIE_ERROR_ELEMENT_NOT_VISIBLE = 1,
  KELPIE_ERROR_TIMEOUT = 2,
  KELPIE_ERROR_NAVIGATION_ERROR = 3,
  KELPIE_ERROR_INVALID_SELECTOR = 4,
  KELPIE_ERROR_INVALID_PARAMS = 5,
  KELPIE_ERROR_WEBVIEW_ERROR = 6,
  KELPIE_ERROR_IFRAME_ACCESS_DENIED = 7,
  KELPIE_ERROR_WATCH_NOT_FOUND = 8,
  KELPIE_ERROR_ANNOTATION_EXPIRED = 9,
  KELPIE_ERROR_PLATFORM_NOT_SUPPORTED = 10,
  KELPIE_ERROR_PERMISSION_REQUIRED = 11,
  KELPIE_ERROR_SHADOW_ROOT_CLOSED = 12,
} KelpieErrorCode;

const char* kelpie_platform_name(KelpiePlatform platform);

const char* kelpie_error_code_name(KelpieErrorCode code);
int32_t kelpie_error_http_status(KelpieErrorCode code);

int32_t kelpie_default_port(void);
const char* kelpie_mdns_service_type(void);
const char* kelpie_api_version_prefix(void);
const char* kelpie_mcp_tool_prefix(void);
int32_t kelpie_cli_mcp_port(void);

#ifdef __cplusplus
}
#endif
