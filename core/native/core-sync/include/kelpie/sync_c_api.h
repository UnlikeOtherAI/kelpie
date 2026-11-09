#pragma once

// Peer-to-peer cookie sync core. See docs/plans/2026-11-09-p2p-cookie-sync.md
// and docs/api/cookie-sync.md.
//
// Every function takes and returns UTF-8 JSON. Returned strings are owned by
// the caller and freed with kelpie_sync_free_string. A failure returns
// {"error":"<CODE>","message":"…"} instead of the documented shape.
//
// A store is not thread-safe. Run every call for one store on one serial
// executor; a merge transaction (plan, engine writes, commit) holds it, and any
// mutating call made while a merge is open fails with BUSY.

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KelpieSyncStore* KelpieSyncStoreRef;

void kelpie_sync_free_string(char* str);

// options: {"subject","replica","launch":bool,"nowMillis"}. Returns NULL and
// writes {"error"} JSON to *error_out (caller frees) when the file cannot be
// read or written. error_out may be NULL.
KelpieSyncStoreRef kelpie_sync_store_open(const char* path, const char* options_json, char** error_out);
void kelpie_sync_store_close(KelpieSyncStoreRef store);

char* kelpie_sync_store_status(KelpieSyncStoreRef store);
void kelpie_sync_store_finish_warmup(KelpieSyncStoreRef store);

// cookies: engine cookies in wire shape. coverage: {"all":true} | {"urls":[…]}.
char* kelpie_sync_store_scan(KelpieSyncStoreRef store, const char* cookies_json,
                             const char* coverage_json, int64_t now_millis);
char* kelpie_sync_store_answer_pull(KelpieSyncStoreRef store, const char* pull_json,
                                    const char* cookies_json, const char* coverage_json,
                                    int64_t now_millis);
char* kelpie_sync_store_build_push(KelpieSyncStoreRef store, const char* watermark_json,
                                   const char* cookies_json, const char* coverage_json,
                                   int64_t now_millis);

char* kelpie_sync_store_plan_merge(KelpieSyncStoreRef store, const char* records_json,
                                   const char* source_json, int64_t now_millis);
char* kelpie_sync_store_commit_merge(KelpieSyncStoreRef store, const char* results_json);
void kelpie_sync_store_abort_merge(KelpieSyncStoreRef store);

char* kelpie_sync_store_watermark(KelpieSyncStoreRef store, const char* replica);

// Stateless helpers.
char* kelpie_sync_validate(const char* kind, const char* json);
char* kelpie_sync_transcript(const char* hello_pair_json);
char* kelpie_sync_account_hints(const char* subject, int64_t now_millis);
char* kelpie_sync_canonical_cookie(const char* cookie_json);

#ifdef __cplusplus
}
#endif
