#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KelpieHandlerContext* KelpieHandlerContextRef;

void kelpie_free_string(char* str);

KelpieHandlerContextRef kelpie_handler_context_create(void);
char* kelpie_handler_context_evaluate_js(KelpieHandlerContextRef ref,
                                           const char* script);
char* kelpie_success_response(const char* json_data);
char* kelpie_error_response(const char* code, const char* message);
void kelpie_handler_context_destroy(KelpieHandlerContextRef ref);

#ifdef __cplusplus
}
#endif
