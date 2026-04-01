#pragma once

#include <stdint.h>

#include "mollotov/protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MollotovMcpRegistry* MollotovMcpRegistryRef;

MollotovMcpRegistryRef mollotov_mcp_registry_create(void);
char* mollotov_mcp_registry_tools_for_platform(MollotovMcpRegistryRef registry, int32_t platform);
int32_t mollotov_mcp_registry_is_available(MollotovMcpRegistryRef registry,
                                           const char* name,
                                           int32_t platform,
                                           const char* engine);
char* mollotov_mcp_registry_get_capabilities(MollotovMcpRegistryRef registry,
                                             int32_t platform,
                                             const char* engine);
void mollotov_mcp_registry_destroy(MollotovMcpRegistryRef registry);
void mollotov_mcp_free_string(char* value);

#ifdef __cplusplus
}
#endif
