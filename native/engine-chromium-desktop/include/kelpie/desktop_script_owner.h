#pragma once
#include <string>
#include <utility>
namespace kelpie {
std::string NewDesktopScriptId();
// Established only after authenticated transport admission, never from request JSON.
class ScopedDesktopScriptOwner {
 public:
  explicit ScopedDesktopScriptOwner(std::string owner) : previous_(std::move(current_)) { current_ = std::move(owner); }
  ~ScopedDesktopScriptOwner() { current_ = std::move(previous_); }
  ScopedDesktopScriptOwner(const ScopedDesktopScriptOwner&) = delete;
  ScopedDesktopScriptOwner& operator=(const ScopedDesktopScriptOwner&) = delete;
  static const std::string& Current() { return current_; }
 private:
  std::string previous_;
  inline static thread_local std::string current_;
};
}
