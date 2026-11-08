#include "kelpie/local_inference.h"
#include <cassert>
#include <iostream>

int main(int argc, char** argv) {
  kelpie::ai::LocalInference engine;
  using json = nlohmann::json;
  assert(engine.Execute("status", {})["loaded"] == false);
  const auto extraction = std::make_shared<std::atomic<bool>>(true);
  const auto person_chat = std::make_shared<std::atomic<bool>>(true);
  extraction->store(false);
  assert(engine.Execute("infer", {{"prompt", "Hello"}}, extraction)["error"]["code"] == "INFERENCE_CANCELLED");
  assert(engine.Execute("status", {}, person_chat)["success"] == true);
  assert(person_chat->load());
  auto* owned = kelpie_local_request_create();
  kelpie_local_request_cancel(owned);
  char* stopped = kelpie_local_execute_owned(&engine, "infer", "{\"prompt\":\"Hello\"}", owned);
  assert(json::parse(stopped)["error"]["code"] == "INFERENCE_CANCELLED");
  std::free(stopped);
  kelpie_local_request_destroy(owned);
  assert(engine.Execute("infer", {{"prompt", "Hello"}})["error"]["code"] == "NO_MODEL_LOADED");
  assert(engine.Execute("infer", {{"prompt", "Hello"}, {"agent", true}})["error"]["code"] == "TOOLS_NOT_SUPPORTED");
  assert(engine.Execute("load", {{"model", "missing.gguf"}})["error"]["code"] == "MODEL_NOT_FOUND");
  assert(engine.Execute("load", {{"model", 123}})["error"]["code"] == "INVALID_PARAM");
  engine.Cancel();
  assert(engine.Execute("unload", {})["success"] == true);
  if (argc > 1) {
    auto loaded = engine.Execute("load", {{"model", argv[1]}, {"contextSize", 512}});
    assert(loaded["success"] == true);
    auto long_request = engine.Execute("infer", {{"prompt", "hello"}, {"maxTokens", 1024}});
    assert(long_request["error"]["code"] == "CONTEXT_TOO_LONG");
    auto answer = engine.Execute("infer", {{"prompt", "What is 2 + 2?"}, {"maxTokens", 32}, {"temperature", 0}});
    std::cout << answer.dump() << std::endl;
    assert(answer["success"] == true);
    assert(!answer["response"].get<std::string>().empty());
    assert(engine.Execute("infer", {{"prompt", "hello"}, {"image", "invalid"}})["error"]["code"] == "INPUT_NOT_SUPPORTED");
    assert(engine.Execute("unload", {})["loaded"] == false);
  }
}
