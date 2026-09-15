#pragma once
#include <cstdint>
#include <optional>
namespace kelpie::windows {
class CeftPumpDeadline {
 public:
  void Schedule(std::int64_t now_ms, std::int64_t delay_ms);
  std::optional<std::int64_t> due_ms() const { return due_ms_; }
  bool ConsumeIfDue(std::int64_t now_ms);
 private: std::optional<std::int64_t> due_ms_;
};
}
