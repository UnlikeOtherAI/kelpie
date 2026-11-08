#pragma once

#include <string>
#include <vector>
#include <nlohmann/json.hpp>

namespace kelpie {

struct ApprovedModel {
  std::string id;
  std::string name;
  std::string hugging_face_repo;
  std::string hugging_face_file;
  int64_t size_bytes;
  double ram_when_loaded_gb;
  std::vector<std::string> capabilities;
  double min_ram_gb;
  double recommended_ram_gb;
  std::string quantization;
  int context_window;
  std::string summary;
  std::string best_for;
  std::string speed_rating;

  std::string download_url() const;
  nlohmann::json to_json() const;
};

struct ModelFitness {
  enum Level { kRecommended, kPossible, kNotRecommended, kNoStorage };
  Level level;
  std::string message;

  nlohmann::json to_json() const;
};

class ModelCatalog {
 public:
  static const std::vector<ApprovedModel>& approved_models();
  static const ApprovedModel* find(const std::string& id);
  static ModelFitness fitness(const ApprovedModel& model,
                              double total_ram_gb,
                              double disk_free_gb);
};

}  // namespace kelpie
