#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KelpieAiManager* KelpieAiManagerRef;

// Lifecycle
KelpieAiManagerRef kelpie_ai_create(const char* models_dir);
void kelpie_ai_destroy(KelpieAiManagerRef mgr);

// String ownership — caller must free returned strings
void kelpie_ai_free_string(char* str);

// HF token
void kelpie_ai_set_hf_token(KelpieAiManagerRef mgr, const char* token);
char* kelpie_ai_get_hf_token(KelpieAiManagerRef mgr);

// Model catalog
char* kelpie_ai_list_approved_models(KelpieAiManagerRef mgr);
char* kelpie_ai_model_fitness(KelpieAiManagerRef mgr,
                                const char* model_id,
                                double total_ram_gb,
                                double disk_free_gb);

// Model store
bool kelpie_ai_is_model_downloaded(KelpieAiManagerRef mgr, const char* model_id);
char* kelpie_ai_model_path(KelpieAiManagerRef mgr, const char* model_id);
bool kelpie_ai_remove_model(KelpieAiManagerRef mgr, const char* model_id);

// Model download (blocking — platform wraps in async)
// Returns NULL on success, error JSON string on failure.
// progress_cb receives (bytes_downloaded, total_bytes, user_data).
typedef void (*KelpieAiDownloadProgressCb)(int64_t downloaded, int64_t total, void* user_data);
char* kelpie_ai_download_model(KelpieAiManagerRef mgr,
                                 const char* model_id,
                                 KelpieAiDownloadProgressCb progress_cb,
                                 void* user_data);

// Ollama
void kelpie_ai_set_ollama_endpoint(KelpieAiManagerRef mgr, const char* endpoint);
bool kelpie_ai_ollama_reachable(KelpieAiManagerRef mgr);
char* kelpie_ai_ollama_list_models(KelpieAiManagerRef mgr);
char* kelpie_ai_ollama_infer(KelpieAiManagerRef mgr,
                               const char* model_name,
                               const char* request_json);

// HF cloud inference
char* kelpie_ai_hf_infer(KelpieAiManagerRef mgr,
                            const char* model_id,
                            const char* request_json);

#ifdef __cplusplus
}
#endif
