#pragma once

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
  void UpdateLatestTitle(const std::string& url, const std::string& title);
  void LoadJson(const std::string& json);
  std::string ToJson() const;
  std::int32_t Count() const;

 private:
  static constexpr std::size_t kMaxEntries = 500;

  std::vector<HistoryEntry> entries_;
  mutable std::mutex mutex_;
};

}  // namespace kelpie
