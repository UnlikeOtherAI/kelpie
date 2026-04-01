#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum MollotovPlatform {
  MOLLOTOV_PLATFORM_IOS = 0,
  MOLLOTOV_PLATFORM_ANDROID = 1,
  MOLLOTOV_PLATFORM_MACOS = 2,
  MOLLOTOV_PLATFORM_LINUX = 3,
  MOLLOTOV_PLATFORM_WINDOWS = 4,
} MollotovPlatform;

typedef enum MollotovErrorCode {
  MOLLOTOV_ERROR_ELEMENT_NOT_FOUND = 0,
  MOLLOTOV_ERROR_ELEMENT_NOT_VISIBLE = 1,
  MOLLOTOV_ERROR_TIMEOUT = 2,
  MOLLOTOV_ERROR_NAVIGATION_ERROR = 3,
  MOLLOTOV_ERROR_INVALID_SELECTOR = 4,
  MOLLOTOV_ERROR_INVALID_PARAMS = 5,
  MOLLOTOV_ERROR_WEBVIEW_ERROR = 6,
  MOLLOTOV_ERROR_IFRAME_ACCESS_DENIED = 7,
  MOLLOTOV_ERROR_WATCH_NOT_FOUND = 8,
  MOLLOTOV_ERROR_ANNOTATION_EXPIRED = 9,
  MOLLOTOV_ERROR_PLATFORM_NOT_SUPPORTED = 10,
  MOLLOTOV_ERROR_PERMISSION_REQUIRED = 11,
  MOLLOTOV_ERROR_SHADOW_ROOT_CLOSED = 12,
} MollotovErrorCode;

const char* mollotov_platform_name(MollotovPlatform platform);

const char* mollotov_error_code_name(MollotovErrorCode code);
int32_t mollotov_error_http_status(MollotovErrorCode code);

int32_t mollotov_default_port(void);
const char* mollotov_mdns_service_type(void);
const char* mollotov_api_version_prefix(void);
const char* mollotov_mcp_tool_prefix(void);
int32_t mollotov_cli_mcp_port(void);

#ifdef __cplusplus
}
#endif
