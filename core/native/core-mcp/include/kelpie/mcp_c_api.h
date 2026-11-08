#pragma once

#include <stdint.h>

#include "kelpie/protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KelpieMcpRegistry* KelpieMcpRegistryRef;

KelpieMcpRegistryRef kelpie_mcp_registry_create(void);
char* kelpie_mcp_registry_tools_for_platform(KelpieMcpRegistryRef registry, int32_t platform);
int32_t kelpie_mcp_registry_is_available(KelpieMcpRegistryRef registry,
                                           const char* name,
                                           int32_t platform,
                                           const char* engine);
char* kelpie_mcp_registry_get_capabilities(KelpieMcpRegistryRef registry,
                                             int32_t platform,
                                             const char* engine);
void kelpie_mcp_registry_destroy(KelpieMcpRegistryRef registry);
void kelpie_mcp_free_string(char* value);

#ifdef __cplusplus
}
#endif
