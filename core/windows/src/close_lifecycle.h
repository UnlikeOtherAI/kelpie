#pragma once

namespace kelpie::windows {

// Coordinates the two shutdown barriers without owning browser or HTTP objects:
// listener admission must drain before durable state is written, and CEF may
// require more than one bounded close attempt after that point.
class CloseLifecycle {
 public:
  void Request() { requested_ = true; }
  bool requested() const { return requested_; }
  bool completed() const { return completed_; }
  bool persisted() const { return persisted_; }

  template <typename Persist, typename Shutdown>
  bool Advance(bool admission_drained, Persist persist, Shutdown shutdown) {
    if (!requested_ || completed_ || !admission_drained) return completed_;
    if (!persisted_) {
      persist();
      persisted_ = true;
    }
    if (!shutdown()) return false;
    completed_ = true;
    return true;
  }

 private:
  bool requested_ = false;
  bool persisted_ = false;
  bool completed_ = false;
};

}  // namespace kelpie::windows