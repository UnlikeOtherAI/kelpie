#pragma once

#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <nlohmann/json.hpp>

namespace kelpie {

// Owned by a live browser tab, never serialized into the restorable session.
// A caller may hold this object while inference runs; Close invalidates that
// completion and erases the conversation even while such a caller survives.
class TabChatSession {
 public:
  struct Turn {
    std::uint64_t token;
    nlohmann::json messages;
  };

  std::optional<Turn> Begin(const std::string& prompt) {
    std::lock_guard lock(mutex_);
    if (closed_ || busy_ || prompt.empty()) return std::nullopt;
    busy_ = true;
    messages_.push_back({{"role", "user"}, {"content", prompt}});
    return Turn{++token_, messages_};
  }

  bool Complete(std::uint64_t token, const std::optional<std::string>& answer) {
    std::lock_guard lock(mutex_);
    if (closed_ || !busy_ || token != token_) return false;
    if (answer) messages_.push_back({{"role", "assistant"}, {"content", *answer}});
    busy_ = false;
    return true;
  }

  nlohmann::json Messages() const {
    std::lock_guard lock(mutex_);
    return messages_;
  }

  void Close() {
    std::lock_guard lock(mutex_);
    closed_ = true;
    busy_ = false;
    messages_.clear();
  }

 private:
  mutable std::mutex mutex_;
  nlohmann::json messages_ = nlohmann::json::array();
  std::uint64_t token_ = 0;
  bool busy_ = false;
  bool closed_ = false;
};

}  // namespace kelpie
