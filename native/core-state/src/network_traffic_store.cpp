#include "mollotov/network_traffic_store.h"

#include <algorithm>
#include <cctype>
#include <limits>

#include <nlohmann/json.hpp>

#include "store_support.h"

namespace mollotov {
namespace {

using json = nlohmann::json;

StringMap ParseHeaders(const json& object,
                       std::initializer_list<const char*> keys) {
  for (const char* key : keys) {
    const auto it = object.find(key);
    if (it == object.end() || !it->is_object()) {
      continue;
    }
    StringMap headers;
    for (auto entry = it->begin(); entry != it->end(); ++entry) {
      if (entry.value().is_string()) {
        headers[entry.key()] = entry.value().get<std::string>();
      }
    }
    return headers;
  }
  return {};
}

json EntryToJsonObject(const TrafficEntry& entry, const std::string& category) {
  return json{
      {"id", entry.id},
      {"method", entry.method},
      {"url", entry.url},
      {"status_code", entry.status_code},
      {"content_type", entry.content_type},
      {"category", category},
      {"request_headers", entry.request_headers},
      {"response_headers", entry.response_headers},
      {"request_body", entry.request_body},
      {"response_body", entry.response_body},
      {"start_time", entry.start_time},
      {"duration", entry.duration},
      {"size", entry.size},
  };
}

}  // namespace

void NetworkTrafficStore::Append(const TrafficEntry& entry) {
  std::lock_guard<std::mutex> lock(mutex_);

  TrafficEntry normalized = entry;
  if (normalized.id.empty()) {
    normalized.id = store_support::GenerateUuidV4();
  }
  normalized.method = NormalizeMethod(normalized.method);
  if (normalized.start_time.empty()) {
    normalized.start_time = store_support::CurrentIso8601Utc();
  }
  normalized.duration = std::max<std::int32_t>(0, normalized.duration);
  normalized.size = std::max<std::int64_t>(0, normalized.size);

  entries_.push_back(std::move(normalized));
  if (entries_.size() > kMaxEntries) {
    const std::size_t removed = entries_.size() - kMaxEntries;
    entries_.erase(entries_.begin(), entries_.begin() + static_cast<long>(removed));
    ClampAfterTrimLocked(removed);
  }
}

void NetworkTrafficStore::AppendDocumentNavigation(const std::string& url,
                                                   std::int32_t status_code,
                                                   const std::string& content_type,
                                                   const StringMap& response_headers,
                                                   std::int64_t size,
                                                   const std::string& start_time,
                                                   std::int32_t duration) {
  Append(TrafficEntry{
      store_support::GenerateUuidV4(),
      "GET",
      url,
      status_code,
      content_type,
      {},
      response_headers,
      "",
      "",
      start_time.empty() ? store_support::CurrentIso8601Utc() : start_time,
      std::max<std::int32_t>(0, duration),
      std::max<std::int64_t>(0, size),
  });
}

void NetworkTrafficStore::Clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  entries_.clear();
  selected_index_.reset();
}

bool NetworkTrafficStore::Select(std::size_t index) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (index >= entries_.size()) {
    return false;
  }
  selected_index_ = index;
  return true;
}

std::optional<TrafficEntry> NetworkTrafficStore::GetSelected() const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!selected_index_.has_value() || *selected_index_ >= entries_.size()) {
    return std::nullopt;
  }
  return entries_[*selected_index_];
}

std::optional<std::size_t> NetworkTrafficStore::SelectedIndex() const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!selected_index_.has_value() || *selected_index_ >= entries_.size()) {
    return std::nullopt;
  }
  return selected_index_;
}

void NetworkTrafficStore::LoadJson(const std::string& json_text) {
  const json parsed = store_support::ParseJson(json_text);

  std::vector<TrafficEntry> loaded;
  if (parsed.is_array()) {
    for (const auto& item : parsed) {
      if (!item.is_object()) {
        continue;
      }
      const std::string url = store_support::StringOrDefault(item, {"url"});
      const std::string method = store_support::StringOrDefault(item, {"method"});
      if (url.empty() || method.empty()) {
        continue;
      }
      loaded.push_back(TrafficEntry{
          store_support::StringOrDefault(item, {"id"}, store_support::GenerateUuidV4()),
          NormalizeMethod(method),
          url,
          store_support::IntOrDefault(item, {"status_code", "statusCode"}),
          store_support::StringOrDefault(item, {"content_type", "contentType"}),
          ParseHeaders(item, {"request_headers", "requestHeaders"}),
          ParseHeaders(item, {"response_headers", "responseHeaders"}),
          store_support::StringOrDefault(item, {"request_body", "requestBody"}),
          store_support::StringOrDefault(item, {"response_body", "responseBody"}),
          store_support::StringOrDefault(item, {"start_time", "startTime"},
                                         store_support::CurrentIso8601Utc()),
          std::max<std::int32_t>(0, store_support::IntOrDefault(item, {"duration"})),
          std::max<std::int64_t>(0, store_support::Int64OrDefault(item, {"size"})),
      });
    }
  }

  if (loaded.size() > kMaxEntries) {
    loaded.erase(loaded.begin(), loaded.begin() + static_cast<long>(loaded.size() - kMaxEntries));
  }

  std::lock_guard<std::mutex> lock(mutex_);
  entries_ = std::move(loaded);
  selected_index_.reset();
}

std::string NetworkTrafficStore::ToJson() const {
  json output = json::array();

  std::lock_guard<std::mutex> lock(mutex_);
  for (const TrafficEntry& entry : entries_) {
    output.push_back(EntryToJsonObject(entry, CategoryForContentType(entry.content_type)));
  }
  return output.dump();
}

std::string NetworkTrafficStore::GetSelectedJson() const {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!selected_index_.has_value() || *selected_index_ >= entries_.size()) {
    return std::string();
  }
  return EntryToJsonObject(entries_[*selected_index_],
                           CategoryForContentType(entries_[*selected_index_].content_type))
      .dump();
}

std::string NetworkTrafficStore::EntryToJson(const TrafficEntry& entry) const {
  return EntryToJsonObject(entry, CategoryForContentType(entry.content_type)).dump();
}

std::string NetworkTrafficStore::ToSummaryJson(const std::optional<std::string>& method,
                                               const std::optional<std::string>& category,
                                               const std::optional<std::string>& status_range,
                                               const std::optional<std::string>& url_pattern) const {
  json output = json::array();

  std::lock_guard<std::mutex> lock(mutex_);
  std::size_t filtered_index = 0;
  for (const TrafficEntry& entry : entries_) {
    const std::string entry_category = CategoryForContentType(entry.content_type);
    if (method.has_value() && NormalizeMethod(*method) != entry.method) {
      continue;
    }
    if (category.has_value() &&
        store_support::Lowercase(*category) != store_support::Lowercase(entry_category)) {
      continue;
    }
    if (!MatchesStatusRange(entry.status_code, status_range)) {
      continue;
    }
    if (url_pattern.has_value() && entry.url.find(*url_pattern) == std::string::npos) {
      continue;
    }

    output.push_back(json{
        {"index", filtered_index++},
        {"method", entry.method},
        {"url", entry.url},
        {"status_code", entry.status_code},
        {"content_type", entry.content_type},
        {"category", entry_category},
        {"duration", entry.duration},
        {"size", entry.size},
    });
  }

  return output.dump();
}

std::int32_t NetworkTrafficStore::Count() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return static_cast<std::int32_t>(entries_.size());
}

std::string NetworkTrafficStore::CategoryForContentType(const std::string& content_type) {
  const std::string normalized = store_support::Lowercase(content_type);
  if (normalized.find("json") != std::string::npos) {
    return "JSON";
  }
  if (normalized.find("html") != std::string::npos) {
    return "HTML";
  }
  if (normalized.find("css") != std::string::npos) {
    return "CSS";
  }
  if (normalized.find("javascript") != std::string::npos ||
      normalized.find("ecmascript") != std::string::npos) {
    return "JS";
  }
  if (normalized.find("image") != std::string::npos) {
    return "Image";
  }
  if (normalized.find("font") != std::string::npos) {
    return "Font";
  }
  if (normalized.find("xml") != std::string::npos) {
    return "XML";
  }
  return "Other";
}

bool NetworkTrafficStore::MatchesStatusRange(std::int32_t status_code,
                                             const std::optional<std::string>& range) {
  if (!range.has_value() || range->empty()) {
    return true;
  }

  const auto dash = range->find('-');
  try {
    if (dash == std::string::npos) {
      return status_code == std::stoi(*range);
    }
    const std::int32_t min = std::stoi(range->substr(0, dash));
    const std::int32_t max = std::stoi(range->substr(dash + 1));
    return status_code >= min && status_code <= max;
  } catch (...) {
    return true;
  }
}

std::string NetworkTrafficStore::NormalizeMethod(const std::string& method) {
  std::string normalized = method;
  std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char ch) {
    return static_cast<char>(std::toupper(ch));
  });
  return normalized;
}

void NetworkTrafficStore::ClampAfterTrimLocked(std::size_t removed_count) {
  if (!selected_index_.has_value()) {
    return;
  }
  if (*selected_index_ < removed_count) {
    selected_index_.reset();
    return;
  }
  *selected_index_ -= removed_count;
  if (*selected_index_ >= entries_.size()) {
    selected_index_.reset();
  }
}

}  // namespace mollotov
