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

  // A registered route may return an explicit platform error for HTTP clients.
  // It is not automatically an MCP capability: callers must opt in to discovery.
  void Register(std::string method, Handler handler, bool callable = true);
  bool Has(std::string_view method) const;
  bool IsCallable(std::string_view method) const;
  Result Dispatch(std::string_view method, const json& params) const;
  std::vector<std::string> RegisteredMethods() const;

 private:
  struct Route {
    Handler handler;
    bool callable = true;
  };

  std::unordered_map<std::string, Route> handlers_;
};

}  // namespace kelpie
