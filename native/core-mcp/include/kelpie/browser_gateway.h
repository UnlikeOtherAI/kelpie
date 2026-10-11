#pragma once
#include <memory>
#include <nlohmann/json.hpp>
namespace kelpie {
// Internal generated reader expression; bindings execute it only in their fixed
// private-world reader. The returned targets are transient DOM objects, not refs.
std::string CollectBrowserSnapshotExpression(const nlohmann::json& options);
// Value-free selector/evidence projection of the same observed DOM objects.
// No reference registry is created; each selector uniquely matches its source node.
std::string CollectBrowserSelectorSnapshotExpression(const nlohmann::json& options);
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
