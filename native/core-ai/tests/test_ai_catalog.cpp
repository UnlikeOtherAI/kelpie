#include "kelpie/ai_c_api.h"
#include <cassert>
#include <iostream>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

void TestCreateDestroy() {
  auto* mgr = kelpie_ai_create("/tmp/test_models");
  assert(mgr != nullptr);
  kelpie_ai_destroy(mgr);
}

void TestListApprovedModels() {
  auto* mgr = kelpie_ai_create("/tmp/test_models");
  char* result = kelpie_ai_list_approved_models(mgr);
  assert(result != nullptr);
  json models = json::parse(result);
  assert(models.is_array());
  assert(models.size() >= 2);
  assert(models[0].contains("id"));
  assert(models[0].contains("name"));
  assert(models[0].contains("hugging_face_repo"));
  assert(models[0].contains("size_bytes"));
  assert(models[0].contains("capabilities"));
  assert(models[0].contains("download_url"));
  kelpie_ai_free_string(result);
  kelpie_ai_destroy(mgr);
}

void TestModelFitnessRecommended() {
  auto* mgr = kelpie_ai_create("/tmp/test_models");
  char* result = kelpie_ai_model_fitness(mgr, "gemma-4-e2b-q4", 32.0, 50.0);
  assert(result != nullptr);
  json fitness = json::parse(result);
  assert(fitness["fitness"] == "recommended");
  kelpie_ai_free_string(result);
  kelpie_ai_destroy(mgr);
}

void TestModelFitnessNoStorage() {
  auto* mgr = kelpie_ai_create("/tmp/test_models");
  char* result = kelpie_ai_model_fitness(mgr, "gemma-4-e2b-q4", 32.0, 0.1);
  assert(result != nullptr);
  json fitness = json::parse(result);
  assert(fitness["fitness"] == "no_storage");
  assert(fitness.contains("message"));
  kelpie_ai_free_string(result);
  kelpie_ai_destroy(mgr);
}

void TestModelFitnessNotRecommended() {
  auto* mgr = kelpie_ai_create("/tmp/test_models");
  char* result = kelpie_ai_model_fitness(mgr, "gemma-4-e2b-q4", 4.0, 50.0);
  assert(result != nullptr);
  json fitness = json::parse(result);
  assert(fitness["fitness"] == "not_recommended");
  kelpie_ai_free_string(result);
  kelpie_ai_destroy(mgr);
}

void TestModelFitnessPossible() {
  auto* mgr = kelpie_ai_create("/tmp/test_models");
  // 12 GB RAM is below recommended 16, but above min 8
  char* result = kelpie_ai_model_fitness(mgr, "gemma-4-e2b-q4", 12.0, 50.0);
  assert(result != nullptr);
  json fitness = json::parse(result);
  assert(fitness["fitness"] == "possible");
  kelpie_ai_free_string(result);
  kelpie_ai_destroy(mgr);
}

int main() {
  TestCreateDestroy();
  TestListApprovedModels();
  TestModelFitnessRecommended();
  TestModelFitnessNoStorage();
  TestModelFitnessNotRecommended();
  TestModelFitnessPossible();
  std::cout << "PASS: test_ai_catalog" << std::endl;
  return 0;
}
