#pragma once
#include <atomic>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>
#include <nlohmann/json.hpp>

namespace kelpie::windows {
struct InferenceError : std::runtime_error {
  std::string code;
  InferenceError(std::string code, std::string message) : std::runtime_error(message), code(std::move(code)) {}
};
struct InferenceURL {
  std::string base;
  std::wstring host;
  std::wstring path;
  unsigned short port;
  bool secure;
  bool loopback;
};
InferenceURL ParseInferenceURL(const std::string& input);
class InferenceTransport {
 public:
  ~InferenceTransport() { Cancel(); }
  nlohmann::json Request(const std::string& base, const std::string& operation,
                        const std::string& key, const nlohmann::json* body = nullptr);
  int Cancel();
 private:
  std::mutex mutex_;
  std::set<void*> requests_;
  std::atomic<unsigned> generation_{0};
};
}
