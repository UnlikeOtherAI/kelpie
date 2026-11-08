#pragma once

#include <string>
#include <nlohmann/json.hpp>

namespace kelpie {

class HfCloudClient {
 public:
  nlohmann::json infer(const std::string& model_id,
                        const std::string& hf_token,
                        const nlohmann::json& request) const;
};

}  // namespace kelpie
