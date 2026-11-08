#pragma once

#include <cstring>
#include <new>
#include <string>

#include <nlohmann/json.hpp>

#if KELPIE_AI_HAS_HTTPLIB
#include "model_store.h"
#include "ollama_client.h"
#endif

namespace kelpie::ai_internal {

using json = nlohmann::json;

inline const char* SafeCString(const char* value) {
  return value == nullptr ? "" : value;
}

inline char* CopyString(const std::string& value) {
  char* buffer = new (std::nothrow) char[value.size() + 1];
  if (buffer == nullptr) return nullptr;
  std::memcpy(buffer, value.c_str(), value.size() + 1);
  return buffer;
}

}  // namespace kelpie::ai_internal

struct KelpieAiManager {
  std::string models_dir;
  std::string hf_token;
  std::string ollama_endpoint = "http://localhost:11434";
#if KELPIE_AI_HAS_HTTPLIB
  kelpie::ModelStore store;
  kelpie::OllamaClient ollama;
#endif

  explicit KelpieAiManager(std::string dir)
      : models_dir(dir)
#if KELPIE_AI_HAS_HTTPLIB
        , store(dir), ollama("http://localhost:11434")
#endif
  {}
};
