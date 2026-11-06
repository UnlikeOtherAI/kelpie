#pragma once

#include <cstring>
#include <cstdio>
#include <cstdint>
#include <limits>
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
// Numeric-only per-run receipt. The raw screenshot never leaves the existing
// capture path; totals saturate rather than wrapping on unexpected input.
class TestScriptPngByteStats {
 public:
  explicit TestScriptPngByteStats(const char* value) : enabled_(value && std::strcmp(value, "1") == 0) {}
  void Add(std::size_t bytes) {
    if (!enabled_) return;
    ++count_;
    const auto value = static_cast<std::uint64_t>(bytes);
    maximum_ = value > maximum_ ? value : maximum_;
    total_ = value > std::numeric_limits<std::uint64_t>::max() - total_
        ? std::numeric_limits<std::uint64_t>::max() : total_ + value;
  }
  ~TestScriptPngByteStats() {
    if (enabled_) std::fprintf(stderr, "KELPIE_TEST_SCRIPT_PNG_BYTES %llu %llu %llu\n",
        static_cast<unsigned long long>(count_), static_cast<unsigned long long>(total_),
        static_cast<unsigned long long>(maximum_));
  }
 private:
  bool enabled_;
  std::uint64_t count_ = 0, total_ = 0, maximum_ = 0;
};
}  // namespace kelpie
