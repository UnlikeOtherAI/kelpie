#include "kelpie/ai_c_api.h"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;

void TestHfToken() {
  auto* mgr = kelpie_ai_create("/tmp/test_ai_store");
  kelpie_ai_set_hf_token(mgr, "hf_test_123");
  char* token = kelpie_ai_get_hf_token(mgr);
  assert(token != nullptr);
  assert(std::string(token) == "hf_test_123");
  kelpie_ai_free_string(token);
  kelpie_ai_destroy(mgr);
}

void TestModelNotDownloaded() {
  fs::create_directories("/tmp/test_ai_store_empty");
  auto* mgr = kelpie_ai_create("/tmp/test_ai_store_empty");
  assert(!kelpie_ai_is_model_downloaded(mgr, "gemma-4-e2b-q4"));
  char* path = kelpie_ai_model_path(mgr, "gemma-4-e2b-q4");
  assert(path != nullptr);
  // Should return expected path even when not downloaded
  std::string p(path);
  assert(p.find("gemma-4-e2b-q4") != std::string::npos);
  assert(p.find("model.gguf") != std::string::npos);
  kelpie_ai_free_string(path);
  kelpie_ai_destroy(mgr);
  fs::remove_all("/tmp/test_ai_store_empty");
}

void TestRemoveModel() {
  std::string dir = "/tmp/test_ai_store_rm";
  fs::create_directories(dir + "/gemma-4-e2b-q4");
  // Write a fake model file > 1 MB
  {
    std::ofstream ofs(dir + "/gemma-4-e2b-q4/model.gguf", std::ios::binary);
    std::string data(2'000'000, 'x');
    ofs.write(data.data(), static_cast<std::streamsize>(data.size()));
  }
  {
    std::ofstream ofs(dir + "/gemma-4-e2b-q4/metadata.json");
    ofs << "{}";
  }

  auto* mgr = kelpie_ai_create(dir.c_str());
  assert(kelpie_ai_is_model_downloaded(mgr, "gemma-4-e2b-q4"));
  assert(kelpie_ai_remove_model(mgr, "gemma-4-e2b-q4"));
  assert(!kelpie_ai_is_model_downloaded(mgr, "gemma-4-e2b-q4"));
  kelpie_ai_destroy(mgr);
  fs::remove_all(dir);
}

void TestDownloadUnknownModel() {
  auto* mgr = kelpie_ai_create("/tmp/test_ai_store_dl");
  char* err = kelpie_ai_download_model(mgr, "nonexistent-model",
                                          nullptr, nullptr);
  assert(err != nullptr);
  std::string errStr(err);
  assert(errStr.find("not_found") != std::string::npos);
  kelpie_ai_free_string(err);
  kelpie_ai_destroy(mgr);
}

int main() {
  TestHfToken();
  TestModelNotDownloaded();
  TestRemoveModel();
  TestDownloadUnknownModel();
  std::cout << "PASS: test_ai_store" << std::endl;
  return 0;
}
