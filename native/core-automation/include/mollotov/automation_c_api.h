#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MollotovHandlerContext* MollotovHandlerContextRef;

void mollotov_free_string(char* str);

MollotovHandlerContextRef mollotov_handler_context_create(void);
char* mollotov_handler_context_evaluate_js(MollotovHandlerContextRef ref,
                                           const char* script);
char* mollotov_success_response(const char* json_data);
char* mollotov_error_response(const char* code, const char* message);
void mollotov_handler_context_destroy(MollotovHandlerContextRef ref);

#ifdef __cplusplus
}
#endif
