#pragma once
#include <cstdint>
#include <optional>
namespace kelpie::windows {
class CefPumpDeadline {
 public:
  bool Schedule(std::int64_t now_ms, std::int64_t delay_ms);
  std::optional<std::int64_t> due_ms() const { return due_ms_; }
  bool ConsumeIfDue(std::int64_t now_ms);
  void Cancel() { due_ms_.reset(); }
 private:
  std::optional<std::int64_t> due_ms_;
};
}
