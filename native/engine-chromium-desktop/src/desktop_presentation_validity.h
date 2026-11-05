#pragma once
#include <functional>
#include <mutex>
#include <string>
#include <utility>

namespace kelpie {
class DesktopPresentationValidity {
 public:
  explicit DesktopPresentationValidity(std::function<bool(const std::string&)> check)
      : check_(std::move(check)) {}
  bool Check(const std::string& owner) {
    std::lock_guard lock(mutex_);
    if (!check_) return false;
    try { return check_(owner); } catch (...) { return false; }
  }
  void Close() {
    std::lock_guard lock(mutex_);
    check_ = {};
  }
 private:
  std::mutex mutex_;
  std::function<bool(const std::string&)> check_;
};
}
