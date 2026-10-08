#include "kelpie/local_inference.h"
#include <cassert>
#include <iostream>

int main(int argc, char** argv) {
  kelpie::ai::LocalInference engine;
  using json = nlohmann::json;
  assert(engine.Execute("status", {})["loaded"] == false);
  assert(engine.Execute("infer", {{"prompt", "Hello"}})["error"]["code"] == "NO_MODEL_LOADED");
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
