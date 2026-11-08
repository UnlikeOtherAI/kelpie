#include "model_catalog.h"

#include <cmath>
#include <sstream>

namespace kelpie {
namespace {

std::string format_gb(double value) {
  double rounded = std::round(value * 10.0) / 10.0;
  if (rounded == std::floor(rounded)) {
    std::ostringstream oss;
    oss << static_cast<int64_t>(rounded);
    return oss.str();
  }
  std::ostringstream oss;
  oss.precision(1);
  oss << std::fixed << rounded;
  return oss.str();
}

std::vector<ApprovedModel> build_catalog() {
  std::vector<ApprovedModel> models;

  models.push_back(ApprovedModel{
      "gemma-4-e2b-q4",
      "Gemma 4 E2B Q4",
      "bartowski/gemma-4-E2B-it-GGUF",
      "gemma-4-E2B-it-Q4_K_M.gguf",
      2'500'000'000LL,
      3.8,
      {"text", "vision", "audio"},
      8.0,
      16.0,
      "Q4_K_M",
      8192,
      "Understands text, images, and speech for local page analysis.",
      "General local browsing assistance with text, vision, and audio input",
      "moderate",
  });

  models.push_back(ApprovedModel{
      "gemma-4-e2b-q8",
      "Gemma 4 E2B Q8",
      "bartowski/gemma-4-E2B-it-GGUF",
      "gemma-4-E2B-it-Q8_0.gguf",
      5'000'000'000LL,
      8.0,
      {"text", "vision", "audio"},
      16.0,
      32.0,
      "Q8_0",
      8192,
      "Higher-quality Gemma 4 build with the same multimodal capabilities.",
      "Accuracy-focused local analysis when memory headroom is available",
      "moderate",
  });

  return models;
}

}  // namespace

std::string ApprovedModel::download_url() const {
  return "https://huggingface.co/" + hugging_face_repo + "/resolve/main/" +
         hugging_face_file;
}

nlohmann::json ApprovedModel::to_json() const {
  return nlohmann::json{
      {"id", id},
      {"name", name},
      {"hugging_face_repo", hugging_face_repo},
      {"hugging_face_file", hugging_face_file},
      {"size_bytes", size_bytes},
      {"ram_when_loaded_gb", ram_when_loaded_gb},
      {"capabilities", capabilities},
      {"min_ram_gb", min_ram_gb},
      {"recommended_ram_gb", recommended_ram_gb},
      {"quantization", quantization},
      {"context_window", context_window},
      {"summary", summary},
      {"best_for", best_for},
      {"speed_rating", speed_rating},
      {"download_url", download_url()},
  };
}

nlohmann::json ModelFitness::to_json() const {
  std::string level_str;
  switch (level) {
    case kRecommended:
      level_str = "recommended";
      break;
    case kPossible:
      level_str = "possible";
      break;
    case kNotRecommended:
      level_str = "not_recommended";
      break;
    case kNoStorage:
      level_str = "no_storage";
      break;
  }
  return nlohmann::json{{"fitness", level_str}, {"message", message}};
}

const std::vector<ApprovedModel>& ModelCatalog::approved_models() {
  static const auto catalog = build_catalog();
  return catalog;
}

const ApprovedModel* ModelCatalog::find(const std::string& id) {
  for (const auto& m : approved_models()) {
    if (m.id == id) return &m;
  }
  return nullptr;
}

ModelFitness ModelCatalog::fitness(const ApprovedModel& model,
                                  double total_ram_gb,
                                  double disk_free_gb) {
  double download_size_gb =
      static_cast<double>(model.size_bytes) / 1'000'000'000.0;

  if (disk_free_gb < download_size_gb) {
    return ModelFitness{
        ModelFitness::kNoStorage,
        "Not enough storage — needs " + format_gb(download_size_gb) +
            " GB, you have " + format_gb(disk_free_gb) + " GB free",
    };
  }

  if (total_ram_gb < model.min_ram_gb) {
    return ModelFitness{
        ModelFitness::kNotRecommended,
        "Not recommended — requires " + format_gb(model.min_ram_gb) +
            " GB RAM, you have " + format_gb(total_ram_gb) + " GB",
    };
  }

  if (total_ram_gb < model.recommended_ram_gb ||
      disk_free_gb < download_size_gb * 1.2) {
    return ModelFitness{
        ModelFitness::kPossible,
        "May run slowly on this device",
    };
  }

  return ModelFitness{ModelFitness::kRecommended, ""};
}

}  // namespace kelpie
