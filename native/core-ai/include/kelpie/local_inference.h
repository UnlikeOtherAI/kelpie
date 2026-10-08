#pragma once

#include <atomic>
#include <mutex>
#include <string>
#include <nlohmann/json.hpp>

struct llama_model;
struct llama_context;

namespace kelpie::ai {
// One bounded CPU context per browser. A competing request fails rather than
// queuing unbounded model work; cancellation does not need the inference lock.
class LocalInference {
 public:
  ~LocalInference();
  nlohmann::json Execute(const std::string& operation, const nlohmann::json& body);
  void Cancel();
 private:
  nlohmann::json Load(const nlohmann::json& body);
  nlohmann::json Infer(const nlohmann::json& body);
  void Unload();
  std::mutex mutex_;
  std::atomic<bool> cancelled_{false};
  llama_model* model_ = nullptr;
  llama_context* context_ = nullptr;
  std::string path_;
};
}

extern "C" {
// JSON strings returned by this bridge are released with kelpie_ai_free_string.
void* kelpie_local_create();
void kelpie_local_destroy(void* engine);
char* kelpie_local_execute(void* engine, const char* operation, const char* body);
void kelpie_local_cancel(void* engine);
}
