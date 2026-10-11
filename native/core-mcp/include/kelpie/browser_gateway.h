#pragma once
#include <memory>
#include <nlohmann/json.hpp>
namespace kelpie {
// One coordinator per browser. Caller serializes begin through terminal completion,
// including its policy callback. next/advance bridge synchronous C++ to async renderers.
class BrowserGateway {
 public:
  explicit BrowserGateway(nlohmann::json config);
  ~BrowserGateway();
  nlohmann::json Begin(nlohmann::json request);
  nlohmann::json BeginMcp(nlohmann::json request);
  nlohmann::json Next() const;
  nlohmann::json Advance(nlohmann::json native_response);
  nlohmann::json Cancel();
  void InvalidateReferences(const std::string& tab_id = {});
  nlohmann::json Capabilities() const;
  nlohmann::json ToolList() const;
  nlohmann::json Extensions(const nlohmann::json& names) const;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
// Shared MCP formatting keeps binary images out of text/structured payloads.
nlohmann::json BrowserMcpResult(const nlohmann::json& response);
}
