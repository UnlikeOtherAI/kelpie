#pragma once
#ifdef __cplusplus
extern "C" {
#endif
void* kelpie_local_create(void);
void kelpie_local_destroy(void* engine);
char* kelpie_local_execute(void* engine, const char* operation, const char* body);
void kelpie_local_cancel(void* engine);
#ifdef __cplusplus
}
#endif
