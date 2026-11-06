#pragma once

#include <cstring>
#include <nlohmann/json.hpp>

namespace kelpie {
// Private to the opt-in test build. Screenshot parameters are built on the
// calling sampler thread before the request is marshalled to CEF.
inline thread_local bool test_script_png_speed = false;
class TestScriptPngSpeedScope {
 public:
  TestScriptPngSpeedScope(bool movie, const char* value) : previous_(test_script_png_speed) {
    test_script_png_speed = movie && value && std::strcmp(value, "1") == 0;
  }
  ~TestScriptPngSpeedScope() { test_script_png_speed = previous_; }
  TestScriptPngSpeedScope(const TestScriptPngSpeedScope&) = delete;
  TestScriptPngSpeedScope& operator=(const TestScriptPngSpeedScope&) = delete;
 private:
  bool previous_;
};
inline void ApplyTestScriptPngSpeed(nlohmann::json& params) {
  if (test_script_png_speed && params.value("format", "") == "png") params["optimizeForSpeed"] = true;
}
}  // namespace kelpie
