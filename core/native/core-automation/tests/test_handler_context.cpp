#include "kelpie/automation_c_api.h"
#include "kelpie/handler_context.h"
#include "kelpie/renderer_interface.h"

#include <cassert>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

class MockRenderer : public kelpie::RendererInterface {
 public:
  std::string next_result;
  std::string last_script;

  std::string EvaluateJs(const std::string& script) override {
    last_script = script;
    return next_result;
  }

  std::vector<std::uint8_t> TakeSnapshot() override {
    return {1, 2, 3};
  }

  void LoadUrl(const std::string& url) override {
    current_url = url;
  }

  std::string CurrentUrl() const override {
    return current_url;
  }

  std::string CurrentTitle() const override {
    return "Mock Title";
  }

  bool IsLoading() const override {
    return false;
  }

  bool CanGoBack() const override {
    return true;
  }

  bool CanGoForward() const override {
    return false;
  }

  void GoBack() override {}
  void GoForward() override {}
  void Reload() override {}

 private:
  std::string current_url;
};

void TestContextTracksRendererPresence() {
  kelpie::HandlerContext context;
  assert(!context.HasRenderer());

  MockRenderer renderer;
  context.SetRenderer(&renderer);
  assert(context.HasRenderer());
  assert(context.Renderer() == &renderer);
}

void TestEvaluateJsReturningStringAndJson() {
  MockRenderer renderer;
  kelpie::HandlerContext context(&renderer);

  renderer.next_result = "plain-result";
  assert(context.EvaluateJsReturningString("document.title") == "plain-result");
  assert(renderer.last_script == "document.title");

  renderer.next_result = R"({"ok":true,"count":2})";
  const auto parsed = context.EvaluateJsReturningJson("window.__result");
  assert(renderer.last_script == "JSON.stringify((window.__result))");
  assert(parsed["ok"] == true);
  assert(parsed["count"] == 2);
}

void TestEvaluateJsReturningJsonFallsBackToEmptyObject() {
  MockRenderer renderer;
  kelpie::HandlerContext context(&renderer);

  renderer.next_result = "not json";
  assert(context.EvaluateJsReturningJson("window.__broken").empty());

  renderer.next_result = "null";
  assert(context.EvaluateJsReturningJson("window.__null").empty());
}

void TestContextThrowsWithoutRendererAndCApiReturnsNull() {
  kelpie::HandlerContext context;

  bool threw = false;
  try {
    (void)context.EvaluateJsReturningString("document.title");
  } catch (const std::runtime_error&) {
    threw = true;
  }
  assert(threw);

  KelpieHandlerContextRef ref = kelpie_handler_context_create();
  assert(ref != nullptr);
  assert(kelpie_handler_context_evaluate_js(ref, "document.title") == nullptr);
  kelpie_handler_context_destroy(ref);
}

}  // namespace

int main() {
  try {
    TestContextTracksRendererPresence();
    TestEvaluateJsReturningStringAndJson();
    TestEvaluateJsReturningJsonFallsBackToEmptyObject();
    TestContextThrowsWithoutRendererAndCApiReturnsNull();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
