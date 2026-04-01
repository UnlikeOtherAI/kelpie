#include "mollotov/history_store.h"

#include <algorithm>

#include <nlohmann/json.hpp>

#include "store_support.h"

namespace mollotov {
namespace {

using json = nlohmann::json;

json HistoryEntryToJson(const HistoryEntry& entry) {
  return json{
      {"id", entry.id},
      {"url", entry.url},
      {"title", entry.title},
      {"timestamp", entry.timestamp},
  };
}

}  // namespace

void HistoryStore::Record(const std::string& url, const std::string& title) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!entries_.empty() && entries_.back().url == url) {
    return;
  }

  entries_.push_back(HistoryEntry{
      store_support::GenerateUuidV4(),
      url,
      title,
      store_support::CurrentIso8601Utc(),
  });
  if (entries_.size() > kMaxEntries) {
    entries_.erase(entries_.begin(), entries_.begin() + static_cast<long>(entries_.size() - kMaxEntries));
  }
}

void HistoryStore::Clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  entries_.clear();
}

void HistoryStore::UpdateLatestTitle(const std::string& url, const std::string& title) {
  const std::string trimmed_title = store_support::Trim(title);

  std::lock_guard<std::mutex> lock(mutex_);
  if (trimmed_title.empty() || entries_.empty()) {
    return;
  }
  HistoryEntry& latest = entries_.back();
  if (latest.url != url || latest.title == trimmed_title) {
    return;
  }
  latest.title = trimmed_title;
}

void HistoryStore::LoadJson(const std::string& json_text) {
  const json parsed = store_support::ParseJson(json_text);

  std::vector<HistoryEntry> loaded;
  if (parsed.is_array()) {
    for (const auto& item : parsed) {
      if (!item.is_object()) {
        continue;
      }
      const std::string url = store_support::StringOrDefault(item, {"url"});
      if (url.empty()) {
        continue;
      }
      loaded.push_back(HistoryEntry{
          store_support::StringOrDefault(item, {"id"}, store_support::GenerateUuidV4()),
          url,
          store_support::StringOrDefault(item, {"title"}),
          store_support::StringOrDefault(item, {"timestamp"},
                                         store_support::CurrentIso8601Utc()),
      });
    }
  }

  if (loaded.size() > kMaxEntries) {
    loaded.erase(loaded.begin(), loaded.begin() + static_cast<long>(loaded.size() - kMaxEntries));
  }

  std::lock_guard<std::mutex> lock(mutex_);
  entries_ = std::move(loaded);
}

std::string HistoryStore::ToJson() const {
  json output = json::array();

  std::lock_guard<std::mutex> lock(mutex_);
  for (auto it = entries_.rbegin(); it != entries_.rend(); ++it) {
    output.push_back(HistoryEntryToJson(*it));
  }
  return output.dump();
}

std::int32_t HistoryStore::Count() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return static_cast<std::int32_t>(entries_.size());
}

}  // namespace mollotov
