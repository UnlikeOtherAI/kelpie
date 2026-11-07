#pragma once
#ifdef __cplusplus
extern "C" {
#endif
typedef struct KelpieConnect* KelpieConnectRef;
/* The caller encrypts and atomically persists each returned state BEFORE dispatch/send.
 * Calls are serialized by the platform coordinator. No credentials enter this core. */
KelpieConnectRef kelpie_connect_create(const char* saved_state, const char* account_reference);
void kelpie_connect_destroy(KelpieConnectRef client);
/* receive: gateway frame; complete: {jobId,attemptId,state,output?,error?};
 * replay: {generation}. Returns {decision,state}; null on failure.
 * receive reserves commands durably in state before returning kind=command.
 * On restore pending commands become UNKNOWN_EFFECTS terminal failures. */
char* kelpie_connect_execute(KelpieConnectRef client, const char* operation, const char* json);
/* Trusted local wall clock seam; remote frame fields can never supply this value. */
char* kelpie_connect_execute_at(KelpieConnectRef client, const char* operation, const char* json, long long wall_clock_ms);
void kelpie_connect_free(char* json);
#ifdef __cplusplus
}
#endif
