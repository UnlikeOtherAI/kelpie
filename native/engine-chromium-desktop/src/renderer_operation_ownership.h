#pragma once
#include <atomic>
#include <cstddef>
#include <memory>
#include <utility>

namespace kelpie {
// Operation's mutex serializes these transitions. Pure internal appearance
// observations remain owned by their callback without fencing public actions.
class RendererOperationOwnership {
 public:
  RendererOperationOwnership(std::shared_ptr<std::atomic<std::size_t>> pending, bool fences_actions = true)
      : pending_(std::move(pending)), fences_actions_(fences_actions) {}
  void MarkUncertain() {
    if (uncertain_ || retired_) return;
    uncertain_ = true;
    if (fences_actions_) pending_->fetch_add(1);
  }
  void Retire() {
    if (retired_) return;
    retired_ = true;
    if (uncertain_ && fences_actions_) pending_->fetch_sub(1);
  }
 private:
  std::shared_ptr<std::atomic<std::size_t>> pending_;
  bool fences_actions_, uncertain_ = false, retired_ = false;
};
}
