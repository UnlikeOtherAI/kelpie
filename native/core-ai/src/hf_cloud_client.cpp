#include "hf_cloud_client.h"

#define CPPHTTPLIB_OPENSSL_SUPPORT
#include <httplib.h>

#include <chrono>

namespace kelpie {

nlohmann::json HfCloudClient::infer(const std::string& model_id,
                                     const std::string& hf_token,
                                     const nlohmann::json& request) const {
  using json = nlohmann::json;

  if (hf_token.empty()) {
    return json{{"error", "auth_required"},
                {"message", "HF cloud inference requires a token."}};
  }

  httplib::SSLClient client("api-inference.huggingface.co");
  client.set_connection_timeout(10);
  client.set_read_timeout(60);

  httplib::Headers headers;
  headers.emplace("Authorization", "Bearer " + hf_token);
  headers.emplace("Content-Type", "application/json");

  // Build request body
  json body;
  if (request.contains("inputs")) {
    body = request;  // Pass through if already in HF format
  } else if (request.contains("prompt")) {
    body["inputs"] = request["prompt"].get<std::string>();
    json params;
    if (request.contains("max_tokens")) {
      params["max_new_tokens"] = request["max_tokens"];
    } else {
      params["max_new_tokens"] = 512;
    }
    if (request.contains("temperature")) {
      params["temperature"] = request["temperature"];
    }
    body["parameters"] = params;
  } else if (request.contains("messages")) {
    // Convert chat format to simple prompt
    std::string prompt;
    for (const auto& msg : request["messages"]) {
      std::string role = msg.value("role", "user");
      std::string content = msg.value("content", "");
      if (role == "system") {
        prompt += content + "\n\n";
      } else if (role == "user") {
        prompt += "User: " + content + "\n";
      } else if (role == "assistant") {
        prompt += "Assistant: " + content + "\n";
      }
    }
    prompt += "Assistant: ";
    body["inputs"] = prompt;
    json params;
    params["max_new_tokens"] = request.value("max_tokens", 512);
    if (request.contains("temperature")) {
      params["temperature"] = request["temperature"];
    }
    body["parameters"] = params;
  }

  const std::string path = "/models/" + model_id;

  auto start = std::chrono::steady_clock::now();
  auto res = client.Post(path, headers, body.dump(), "application/json");
  auto end = std::chrono::steady_clock::now();
  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                end - start)
                .count();

  if (!res) {
    return json{{"error", "network"},
                {"message", "Connection to HF Inference API failed"}};
  }

  if (res->status == 401 || res->status == 403) {
    return json{{"error", "auth_required"},
                {"message", "Hugging Face rejected your token."}};
  }

  if (res->status == 503) {
    // Model is loading
    json error_body;
    try {
      error_body = json::parse(res->body);
    } catch (...) {
    }
    std::string msg = "Model is loading, try again in a moment.";
    if (error_body.contains("estimated_time")) {
      msg += " Estimated: " +
             std::to_string(error_body["estimated_time"].get<int>()) + "s";
    }
    return json{{"error", "model_loading"}, {"message", msg}};
  }

  if (res->status != 200) {
    return json{
        {"error", "http"},
        {"message",
         "HTTP " + std::to_string(res->status) + ": " +
             res->body.substr(0, 200)}};
  }

  // Parse response
  json resp;
  try {
    resp = json::parse(res->body);
  } catch (...) {
    return json{{"error", "parse"},
                {"message", "Invalid JSON response from HF"}};
  }

  // HF returns [{"generated_text": "..."}] for text generation
  std::string text;
  if (resp.is_array() && !resp.empty() &&
      resp[0].contains("generated_text")) {
    text = resp[0]["generated_text"].get<std::string>();
  } else if (resp.is_object() && resp.contains("generated_text")) {
    text = resp["generated_text"].get<std::string>();
  } else {
    text = res->body;  // Return raw body as fallback
  }

  return json{{"response", text},
              {"inference_time_ms", ms},
              {"backend", "hf_cloud"},
              {"model_id", model_id}};
}

}  // namespace kelpie
