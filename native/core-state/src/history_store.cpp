#include "kelpie/history_store.h"

#include <algorithm>
#include <unordered_set>

#include <nlohmann/json.hpp>

#include "store_support.h"

namespace kelpie {
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
  if (url.empty() || url == "about:blank") {
    return;
  }
  const std::string normalized = store_support::NormalizeUrl(url);
  std::lock_guard<std::mutex> lock(mutex_);
  // Remove any existing entry for this URL so revisiting moves it to the top.
  // Use normalized form so that trailing-slash, empty-query, and empty-fragment
  // variants are treated as the same URL.
  entries_.erase(
      std::remove_if(entries_.begin(), entries_.end(),
                     [&normalized](const HistoryEntry& e) {
                       return store_support::NormalizeUrl(e.url) == normalized;
                     }),
      entries_.end());

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

bool HistoryStore::RemoveById(const std::string& id) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = std::remove_if(entries_.begin(), entries_.end(),
                           [&id](const HistoryEntry& e) { return e.id == id; });
  if (it == entries_.end()) {
    return false;
  }
  entries_.erase(it, entries_.end());
  return true;
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
    // JSON is exported newest-first; skipping duplicate URLs keeps the most recent visit.
    std::unordered_set<std::string> seen_urls;
    for (const auto& item : parsed) {
      if (!item.is_object()) {
        continue;
      }
      const std::string url = store_support::StringOrDefault(item, {"url"});
      if (url.empty()) {
        continue;
      }
      const std::string normalized = store_support::NormalizeUrl(url);
      if (!seen_urls.insert(normalized).second) {
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

}  // namespace kelpie
