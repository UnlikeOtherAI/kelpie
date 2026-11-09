#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace kelpie {

struct HistoryEntry {
  std::string id;
  std::string url;
  std::string title;
  std::string timestamp;
};

class HistoryStore {
 public:
  void Record(const std::string& url, const std::string& title);
  void Clear();
  bool RemoveById(const std::string& id);
  void UpdateLatestTitle(const std::string& url, const std::string& title);
  std::string BestUrlCompletion(const std::string& query) const;
  void LoadJson(const std::string& json);
  std::string ToJson() const;
  std::int32_t Count() const;
  // Increments on every Clear(). Data derived from history, such as the start
  // page's site previews, compares it to notice that history was cleared.
  std::uint64_t ClearGeneration() const { return clear_generation_.load(); }

 private:
  static constexpr std::size_t kMaxEntries = 500;

  std::vector<HistoryEntry> entries_;
  std::atomic<std::uint64_t> clear_generation_{0};
  mutable std::mutex mutex_;
};

}  // namespace kelpie
