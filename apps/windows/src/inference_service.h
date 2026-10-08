#pragma once
#include "inference_transport.h"
#include "kelpie/local_inference.h"
#include "kelpie/desktop_router.h"
#include <filesystem>
#include <functional>
#include <map>
#include <mutex>

namespace kelpie::windows {
class InferenceService {
 public:
  using json = nlohmann::json;
  using Request = std::function<json(const std::string&, const std::string&, const std::string&, const json*)>;
  explicit InferenceService(std::filesystem::path profile, Request request = {});
  void Register(DesktopRouter& router);
  json Execute(const std::string& method, const json& body = json::object());
  void Cancel();
 private:
  json Dispatch(const std::string& method, const json& body);
  json& Endpoint(const std::string& id);
  json Public(const json& endpoint);
  json Save(const json& body);
  json Models(json& endpoint);
  json Probe(json& endpoint, bool generate);
  json Status();
  json Infer(const json& body);
  json Chat(const json& endpoint, const json& messages, const json& body);
  void Persist();
  std::filesystem::path store_;
  std::mutex mutex_;
  json settings_;
  std::map<std::string, json> health_;
  InferenceTransport transport_;
  Request request_;
  kelpie::ai::LocalInference local_;
  DesktopRouter* router_ = nullptr;
  std::atomic<bool> cancelled_{false};
};
}
