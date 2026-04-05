#include "ollama_client.h"

#include <httplib.h>
#include <algorithm>
#include <stdexcept>

namespace kelpie {

OllamaClient::OllamaClient(std::string endpoint)
    : endpoint_(std::move(endpoint)) {
  parse_endpoint();
}

void OllamaClient::set_endpoint(const std::string& endpoint) {
  endpoint_ = endpoint;
  parse_endpoint();
}

void OllamaClient::parse_endpoint() {
  // Expected format: http://host:port
  std::string url = endpoint_;

  // Strip trailing slash
  while (!url.empty() && url.back() == '/') {
    url.pop_back();
  }

  // Remove scheme
  std::string host_port;
  if (url.rfind("http://", 0) == 0) {
    host_port = url.substr(7);
  } else if (url.rfind("https://", 0) == 0) {
    host_port = url.substr(8);
  } else {
    host_port = url;
  }

  // Split host:port
  auto colon = host_port.rfind(':');
  if (colon != std::string::npos && colon > 0) {
    host_ = host_port.substr(0, colon);
    try {
      port_ = std::stoi(host_port.substr(colon + 1));
    } catch (...) {
      port_ = 11434;
    }
  } else {
    host_ = host_port;
    port_ = 11434;
  }

  // Normalize stored endpoint
  endpoint_ = "http://" + host_ + ":" + std::to_string(port_);
}

bool OllamaClient::is_reachable() const {
  httplib::Client cli(host_, port_);
  cli.set_connection_timeout(2, 0);
  cli.set_read_timeout(2, 0);

  auto res = cli.Get("/api/tags");
  return res && res->status >= 200 && res->status < 300;
}

static bool has_vision_capability(const std::string& name) {
  std::string lower = name;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  return lower.find("llava") != std::string::npos ||
         lower.find("bakllava") != std::string::npos ||
         lower.find("moondream") != std::string::npos ||
         lower.find("gemma") != std::string::npos;
}

nlohmann::json OllamaClient::list_models() const {
  httplib::Client cli(host_, port_);
  cli.set_connection_timeout(2, 0);
  cli.set_read_timeout(5, 0);

  auto res = cli.Get("/api/tags");
  if (!res || res->status < 200 || res->status >= 300) {
    throw std::runtime_error("Failed to reach Ollama at " + endpoint_);
  }

  auto body = nlohmann::json::parse(res->body);
  nlohmann::json result = nlohmann::json::array();

  if (body.contains("models") && body["models"].is_array()) {
    for (const auto& m : body["models"]) {
      nlohmann::json entry;
      entry["name"] = m.value("name", "");
      entry["size"] = m.value("size", 0);

      nlohmann::json caps = nlohmann::json::array();
      caps.push_back("text");
      if (has_vision_capability(entry["name"].get<std::string>())) {
        caps.push_back("vision");
      }
      entry["capabilities"] = caps;

      result.push_back(entry);
    }
  }

  return result;
}

nlohmann::json OllamaClient::infer(const std::string& model_name,
                                    const nlohmann::json& request) const {
  httplib::Client cli(host_, port_);
  cli.set_connection_timeout(5, 0);
  cli.set_read_timeout(300, 0);  // Inference can take minutes

  nlohmann::json body;
  body["model"] = model_name;
  body["stream"] = false;

  std::string api_path;
  if (request.contains("messages")) {
    api_path = "/api/chat";
    body["messages"] = request["messages"];
  } else {
    api_path = "/api/generate";
    body["prompt"] = request.value("prompt", "");
  }

  auto res = cli.Post(api_path, body.dump(), "application/json");
  if (!res || res->status < 200 || res->status >= 300) {
    throw std::runtime_error("Ollama inference failed at " + endpoint_ +
                             api_path);
  }

  auto resp = nlohmann::json::parse(res->body);

  nlohmann::json result;

  // Extract response text
  if (resp.contains("message") && resp["message"].contains("content")) {
    result["response"] = resp["message"]["content"];
  } else if (resp.contains("response")) {
    result["response"] = resp["response"];
  } else {
    result["response"] = "";
  }

  // Convert total_duration from nanoseconds to milliseconds
  int64_t total_ns = resp.value("total_duration", static_cast<int64_t>(0));
  result["inference_time_ms"] = total_ns / 1000000;

  result["backend"] = "ollama";
  result["prompt_eval_count"] = resp.value("prompt_eval_count", 0);
  result["eval_count"] = resp.value("eval_count", 0);

  return result;
}

}  // namespace kelpie
