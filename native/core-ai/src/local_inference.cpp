#include "kelpie/local_inference.h"
#include <llama.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <memory>
#include <thread>
#include <vector>

namespace kelpie::ai {
using json = nlohmann::json;
namespace {
struct Failure : std::runtime_error {
  std::string code;
  Failure(std::string code, std::string message) : std::runtime_error(message), code(std::move(code)) {}
};
json Error(const std::string& code, const std::string& message) {
  return {{"success", false}, {"error", {{"code", code}, {"message", message}}}};
}
std::string FormatPrompt(llama_model* model, const json& body) {
  std::vector<std::pair<std::string, std::string>> owned;
  if (body.contains("messages")) {
    if (!body["messages"].is_array()) throw Failure("INVALID_PARAM", "messages must be an array");
    for (const auto& message : body["messages"]) {
      const auto role = message.at("role").get<std::string>();
      if (role != "user" && role != "assistant" && role != "system")
        throw Failure("INVALID_PARAM", "Local chat accepts system, user and assistant messages");
      owned.emplace_back(role, message.at("content").get<std::string>());
    }
  }
  std::string prompt = body.value("prompt", "");
  const auto text = body.value("text", "");
  if (!text.empty()) prompt += "\n\n" + text;
  if (!prompt.empty()) owned.emplace_back("user", prompt);
  if (owned.empty()) throw Failure("MISSING_PARAM", "prompt or messages is required");
  std::vector<llama_chat_message> messages;
  size_t bytes = 0;
  for (const auto& message : owned) {
    bytes += message.second.size();
    messages.push_back({message.first.c_str(), message.second.c_str()});
  }
  if (bytes > 1024 * 1024) throw Failure("CONTEXT_TOO_LONG", "Input exceeds the local model limit");
  const char* format = llama_model_chat_template(model, nullptr);
  if (!format) throw Failure("MODEL_TEMPLATE_UNSUPPORTED", "Use an instruction GGUF with a supported chat template");
  std::vector<char> output(bytes + messages.size() * 256 + 1024);
  int size = llama_chat_apply_template(format, messages.data(), messages.size(), true, output.data(), output.size());
  if (size < 0) throw Failure("MODEL_TEMPLATE_UNSUPPORTED", "This GGUF chat template is not supported");
  if (static_cast<size_t>(size) > output.size()) {
    output.resize(size);
    size = llama_chat_apply_template(format, messages.data(), messages.size(), true, output.data(), output.size());
  }
  return std::string(output.data(), size);
}
}

LocalInference::~LocalInference() { Cancel(); std::lock_guard lock(mutex_); Unload(); }
void LocalInference::Cancel() { cancelled_ = true; }
void LocalInference::Unload() {
  if (context_) llama_free(context_);
  if (model_) llama_model_free(model_);
  context_ = nullptr; model_ = nullptr; path_.clear();
}
json LocalInference::Execute(const std::string& operation, const json& body) {
  std::unique_lock lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) return Error("AI_BUSY", "A local model operation is already running");
  try {
    if (operation == "load") return Load(body);
    if (operation == "infer") return Infer(body);
    if (operation == "unload") Unload();
    else if (operation != "status") throw Failure("INVALID_PARAM", "Unknown local inference operation");
    return {{"success", true}, {"backend", "native"}, {"loaded", model_ != nullptr},
            {"model", path_}, {"capabilities", model_ ? json::array({"text"}) : json::array()}};
  } catch (const Failure& error) { return Error(error.code, error.what()); }
    catch (const json::exception&) { return Error("INVALID_PARAM", "Invalid local inference parameters"); }
    catch (const std::exception&) { return Error("AI_INFERENCE_FAILED", "Local model operation failed"); }
}
json LocalInference::Load(const json& body) {
  const auto path = body.at("model").get<std::string>();
  if (path.empty() || path.find('\0') != std::string::npos ||
      !std::filesystem::is_regular_file(std::filesystem::u8path(path)))
    throw Failure("MODEL_NOT_FOUND", "Select an existing GGUF model file");
  const int context = body.value("contextSize", 2048);
  if (context < 256 || context > 8192) throw Failure("INVALID_PARAM", "contextSize must be 256 through 8192");
  static std::once_flag init;
  std::call_once(init, [] { llama_backend_init(); });
  cancelled_ = false;
  auto params = llama_model_default_params();
  params.n_gpu_layers = 0; // Portable CPU baseline on all supported devices.
  params.progress_callback = [](float, void* state) { return !static_cast<LocalInference*>(state)->cancelled_.load(); };
  params.progress_callback_user_data = this;
  std::unique_ptr<llama_model, decltype(&llama_model_free)> next(llama_model_load_from_file(path.c_str(), params), llama_model_free);
  if (!next) throw Failure(cancelled_ ? "INFERENCE_CANCELLED" : "MODEL_LOAD_FAILED", "Could not load this GGUF model; try a smaller model or a LAN endpoint");
  auto settings = llama_context_default_params();
  settings.n_ctx = context;
  settings.n_batch = 256;
  settings.n_threads = settings.n_threads_batch = std::max(1u, std::min(4u, std::thread::hardware_concurrency()));
  settings.abort_callback = [](void* state) { return static_cast<LocalInference*>(state)->cancelled_.load(); };
  settings.abort_callback_data = this;
  auto* next_context = llama_init_from_model(next.get(), settings);
  if (!next_context) throw Failure("MODEL_LOAD_FAILED", "Not enough memory for this context; use a smaller model or LAN endpoint");
  Unload(); model_ = next.release(); context_ = next_context; path_ = path;
  return {{"success", true}, {"backend", "native"}, {"model", path}, {"loaded", true}, {"contextSize", llama_n_ctx(context_)}};
}
json LocalInference::Infer(const json& body) {
  if (!model_) throw Failure("NO_MODEL_LOADED", "Load a GGUF model first");
  for (const auto* key : {"image", "images", "audio"})
    if (body.contains(key) && !body[key].is_null()) throw Failure("INPUT_NOT_SUPPORTED", "Local GGUF inference currently accepts text only");
  const auto started = std::chrono::steady_clock::now();
  const auto prompt = FormatPrompt(model_, body);
  const auto* vocab = llama_model_get_vocab(model_);
  const int count = -llama_tokenize(vocab, prompt.data(), prompt.size(), nullptr, 0, true, true);
  const int limit = body.value("maxTokens", 256);
  if (limit < 1 || limit > 4096) throw Failure("INVALID_PARAM", "maxTokens must be 1 through 4096");
  if (count <= 0 || count + limit > static_cast<int>(llama_n_ctx(context_)))
    throw Failure("CONTEXT_TOO_LONG", "Input plus maxTokens exceeds the loaded context; shorten the input");
  std::vector<llama_token> tokens(count);
  if (llama_tokenize(vocab, prompt.data(), prompt.size(), tokens.data(), count, true, true) != count)
    throw Failure("AI_INFERENCE_FAILED", "Could not tokenize the prompt");
  cancelled_ = false;
  llama_memory_clear(llama_get_memory(context_), true);
  const float temperature = body.value("temperature", 0.7f);
  if (!std::isfinite(temperature) || temperature < 0 || temperature > 2)
    throw Failure("INVALID_PARAM", "temperature must be between 0 and 2");
  std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(
      llama_sampler_chain_init(llama_sampler_chain_default_params()), llama_sampler_free);
  if (temperature == 0) llama_sampler_chain_add(sampler.get(), llama_sampler_init_greedy());
  else {
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_k(40));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
  }
  auto decode = [&](llama_token* data, int size) {
    if (cancelled_) throw Failure("INFERENCE_CANCELLED", "Inference was cancelled");
    if (std::chrono::steady_clock::now() - started > std::chrono::minutes(15))
      throw Failure("INFERENCE_TIMEOUT", "Local inference timed out");
    if (llama_decode(context_, llama_batch_get_one(data, size)) != 0)
      throw Failure(cancelled_ ? "INFERENCE_CANCELLED" : "AI_INFERENCE_FAILED", "Local model evaluation stopped");
  };
  for (int offset = 0; offset < count; offset += 256) decode(tokens.data() + offset, std::min(256, count - offset));
  std::string output;
  int generated = 0;
  for (; generated < limit; ++generated) {
    auto token = llama_sampler_sample(sampler.get(), context_, -1);
    if (llama_vocab_is_eog(vocab, token)) break;
    char buffer[256];
    int size = llama_token_to_piece(vocab, token, buffer, sizeof(buffer), 0, true);
    if (size < 0) {
      std::vector<char> large(-size);
      size = llama_token_to_piece(vocab, token, large.data(), large.size(), 0, true);
      if (size > 0) output.append(large.data(), size);
    } else output.append(buffer, size);
    if (generated + 1 < limit) decode(&token, 1);
  }
  return {{"success", true}, {"backend", "native"}, {"response", output}, {"model", path_},
          {"tokensUsed", generated}, {"finishReason", generated == limit ? "length" : "stop"},
          {"inferenceTimeMs", std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started).count()}};
}
}

extern "C" void* kelpie_local_create() { try { return new kelpie::ai::LocalInference(); } catch (...) { return nullptr; } }
extern "C" void kelpie_local_destroy(void* engine) { delete static_cast<kelpie::ai::LocalInference*>(engine); }
extern "C" void kelpie_local_cancel(void* engine) { if (engine) static_cast<kelpie::ai::LocalInference*>(engine)->Cancel(); }
extern "C" char* kelpie_local_execute(void* engine, const char* operation, const char* body) {
  try {
    const auto result = engine ? static_cast<kelpie::ai::LocalInference*>(engine)->Execute(operation, nlohmann::json::parse(body))
        : nlohmann::json({{"success", false}, {"error", {{"code", "AI_UNAVAILABLE"}, {"message", "Local engine unavailable"}}}});
    // A token limit may split a UTF-8 character; JSON replaces only that incomplete suffix.
    const auto text = result.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    auto* copy = static_cast<char*>(std::malloc(text.size() + 1));
    if (copy) std::memcpy(copy, text.c_str(), text.size() + 1);
    return copy;
  } catch (...) { return nullptr; }
}
