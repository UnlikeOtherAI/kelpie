#pragma once

#include <string>
#include <nlohmann/json.hpp>

namespace kelpie {

class OllamaClient {
 public:
  explicit OllamaClient(std::string endpoint = "http://localhost:11434");

  void set_endpoint(const std::string& endpoint);
  const std::string& endpoint() const { return endpoint_; }

  bool is_reachable() const;
  nlohmann::json list_models() const;
  nlohmann::json infer(const std::string& model_name,
                        const nlohmann::json& request) const;

 private:
  std::string endpoint_;
  std::string host_;
  int port_ = 11434;
  void parse_endpoint();
};

}  // namespace kelpie
