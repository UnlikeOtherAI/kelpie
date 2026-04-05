#pragma once

#include <functional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie {

class DesktopRouter {
 public:
  using json = nlohmann::json;
  using Handler = std::function<json(const json&)>;

  struct Result {
    int status_code = 200;
    json body = json::object();
  };

  void Register(std::string method, Handler handler);
  bool Has(std::string_view method) const;
  Result Dispatch(std::string_view method, const json& params) const;
  std::vector<std::string> RegisteredMethods() const;

 private:
  std::unordered_map<std::string, Handler> handlers_;
};

}  // namespace kelpie
