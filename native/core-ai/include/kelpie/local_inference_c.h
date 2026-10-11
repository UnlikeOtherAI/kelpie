#pragma once
#ifdef __cplusplus
extern "C" {
#endif
void* kelpie_local_create(void);
void kelpie_local_destroy(void* engine);
char* kelpie_local_execute(void* engine, const char* operation, const char* body);
void kelpie_local_cancel(void* engine);
void* kelpie_local_request_create(void);
void kelpie_local_request_cancel(void* request);
void kelpie_local_request_destroy(void* request);
char* kelpie_local_execute_owned(void* engine, const char* operation, const char* body, void* request);
#ifdef __cplusplus
}
#endif
