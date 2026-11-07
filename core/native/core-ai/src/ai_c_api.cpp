#include "kelpie/ai_c_api.h"
#include "ai_c_api_internal.h"
#if KELPIE_AI_HAS_HTTPLIB
#include "hf_cloud_client.h"
#endif
#include "model_catalog.h"

extern "C" {

KelpieAiManagerRef kelpie_ai_create(const char* models_dir) {
  try {
    return new KelpieAiManager(
        kelpie::ai_internal::SafeCString(models_dir));
  } catch (...) {
    return nullptr;
  }
}

void kelpie_ai_destroy(KelpieAiManagerRef mgr) {
  delete mgr;
}

void kelpie_ai_free_string(char* str) {
  delete[] str;
}

// --- stubs (filled in by later tasks) ---

void kelpie_ai_set_hf_token(KelpieAiManagerRef mgr, const char* token) {
  if (!mgr) return;
  mgr->hf_token = kelpie::ai_internal::SafeCString(token);
}

char* kelpie_ai_get_hf_token(KelpieAiManagerRef mgr) {
  if (!mgr) return nullptr;
  return kelpie::ai_internal::CopyString(mgr->hf_token);
}
char* kelpie_ai_list_approved_models(KelpieAiManagerRef mgr) {
  if (!mgr) return nullptr;
  try {
    nlohmann::json arr = nlohmann::json::array();
    for (const auto& m : kelpie::ModelCatalog::approved_models()) {
      arr.push_back(m.to_json());
    }
    return kelpie::ai_internal::CopyString(arr.dump());
  } catch (...) {
    return nullptr;
  }
}

char* kelpie_ai_model_fitness(KelpieAiManagerRef mgr, const char* model_id,
                                double total_ram_gb, double disk_free_gb) {
  if (!mgr) return nullptr;
  try {
    const auto* model = kelpie::ModelCatalog::find(
        kelpie::ai_internal::SafeCString(model_id));
    if (!model) return nullptr;
    auto fit = kelpie::ModelCatalog::fitness(*model, total_ram_gb, disk_free_gb);
    return kelpie::ai_internal::CopyString(fit.to_json().dump());
  } catch (...) {
    return nullptr;
  }
}
#if KELPIE_AI_HAS_HTTPLIB
bool kelpie_ai_is_model_downloaded(KelpieAiManagerRef mgr, const char* model_id) {
  if (!mgr) return false;
  try {
    return mgr->store.is_downloaded(kelpie::ai_internal::SafeCString(model_id));
  } catch (...) {
    return false;
  }
}

char* kelpie_ai_model_path(KelpieAiManagerRef mgr, const char* model_id) {
  if (!mgr) return nullptr;
  try {
    return kelpie::ai_internal::CopyString(
        mgr->store.model_path(kelpie::ai_internal::SafeCString(model_id)));
  } catch (...) {
    return nullptr;
  }
}

bool kelpie_ai_remove_model(KelpieAiManagerRef mgr, const char* model_id) {
  if (!mgr) return false;
  try {
    return mgr->store.remove(kelpie::ai_internal::SafeCString(model_id));
  } catch (...) {
    return false;
  }
}

char* kelpie_ai_download_model(KelpieAiManagerRef mgr, const char* model_id,
                                  KelpieAiDownloadProgressCb progress_cb,
                                  void* user_data) {
  if (!mgr) return nullptr;
  try {
    auto cb = progress_cb
        ? kelpie::DownloadProgressCb([=](int64_t dl, int64_t total) {
            progress_cb(dl, total, user_data);
          })
        : kelpie::DownloadProgressCb{};
    std::string err = mgr->store.download(
        kelpie::ai_internal::SafeCString(model_id), mgr->hf_token, cb);
    return err.empty() ? nullptr : kelpie::ai_internal::CopyString(err);
  } catch (...) {
    return nullptr;
  }
}
void kelpie_ai_set_ollama_endpoint(KelpieAiManagerRef mgr, const char* endpoint) {
  if (!mgr) return;
  mgr->ollama.set_endpoint(kelpie::ai_internal::SafeCString(endpoint));
  mgr->ollama_endpoint = mgr->ollama.endpoint();
}

bool kelpie_ai_ollama_reachable(KelpieAiManagerRef mgr) {
  if (!mgr) return false;
  try {
    return mgr->ollama.is_reachable();
  } catch (...) {
    return false;
  }
}

char* kelpie_ai_ollama_list_models(KelpieAiManagerRef mgr) {
  if (!mgr) return nullptr;
  try {
    auto models = mgr->ollama.list_models();
    return kelpie::ai_internal::CopyString(models.dump());
  } catch (...) {
    return nullptr;
  }
}

char* kelpie_ai_ollama_infer(KelpieAiManagerRef mgr, const char* model_name,
                                const char* request_json) {
  if (!mgr) return nullptr;
  try {
    auto req = nlohmann::json::parse(kelpie::ai_internal::SafeCString(request_json));
    auto result = mgr->ollama.infer(kelpie::ai_internal::SafeCString(model_name), req);
    return kelpie::ai_internal::CopyString(result.dump());
  } catch (...) {
    return nullptr;
  }
}
char* kelpie_ai_hf_infer(KelpieAiManagerRef mgr, const char* model_id,
                            const char* request_json) {
  if (!mgr) return nullptr;
  try {
    auto req = nlohmann::json::parse(
        kelpie::ai_internal::SafeCString(request_json));
    kelpie::HfCloudClient client;
    auto result = client.infer(
        kelpie::ai_internal::SafeCString(model_id),
        mgr->hf_token, req);
    return kelpie::ai_internal::CopyString(result.dump());
  } catch (...) {
    return nullptr;
  }
}
#else
// Stubs when httplib is disabled (Android — platform handles HTTP via OkHttp)
bool kelpie_ai_is_model_downloaded(KelpieAiManagerRef, const char*) { return false; }
char* kelpie_ai_model_path(KelpieAiManagerRef, const char*) { return nullptr; }
bool kelpie_ai_remove_model(KelpieAiManagerRef, const char*) { return false; }
char* kelpie_ai_download_model(KelpieAiManagerRef, const char*,
                                  KelpieAiDownloadProgressCb, void*) { return nullptr; }
void kelpie_ai_set_ollama_endpoint(KelpieAiManagerRef, const char*) {}
bool kelpie_ai_ollama_reachable(KelpieAiManagerRef) { return false; }
char* kelpie_ai_ollama_list_models(KelpieAiManagerRef) { return nullptr; }
char* kelpie_ai_ollama_infer(KelpieAiManagerRef, const char*, const char*) { return nullptr; }
char* kelpie_ai_hf_infer(KelpieAiManagerRef, const char*, const char*) { return nullptr; }
#endif

}  // extern "C"
