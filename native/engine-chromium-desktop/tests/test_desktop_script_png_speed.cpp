#include "desktop_test_script_png_speed.h"
#include <cassert>
#include <thread>

int main() {
  using namespace kelpie;
  using Json = nlohmann::json;
  auto apply = [](const char* format) {
    Json params = {{"format", format}, {"captureBeyondViewport", false}};
    ApplyTestScriptPngSpeed(params);
    return params;
  };
  assert(!apply("png").contains("optimizeForSpeed"));
  {
    TestScriptPngSpeedScope disabled(false, "1");
    assert(!apply("png").contains("optimizeForSpeed"));
  }
  {
    TestScriptPngSpeedScope invalid(true, "true");
    assert(!apply("png").contains("optimizeForSpeed"));
  }
  {
    TestScriptPngSpeedScope enabled(true, "1");
    assert(apply("png").at("optimizeForSpeed") == true);
    assert(!apply("jpeg").contains("optimizeForSpeed"));
    std::thread other([&] { assert(!apply("png").contains("optimizeForSpeed")); });
    other.join();
    {
      TestScriptPngSpeedScope nested(false, "1");
      assert(!apply("png").contains("optimizeForSpeed"));
    }
    assert(apply("png").at("optimizeForSpeed") == true);
  }
  assert(!apply("png").contains("optimizeForSpeed"));
}
