#pragma once

#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "mollotov/types.h"

namespace mollotov {

struct TrafficEntry {
  std::string id;
  std::string method;
  std::string url;
  std::int32_t status_code = 0;
  std::string content_type;
  StringMap request_headers;
  StringMap response_headers;
  std::string request_body;
  std::string response_body;
  std::string start_time;
  std::int32_t duration = 0;
  std::int64_t size = 0;
};

class NetworkTrafficStore {
 public:
  void Append(const TrafficEntry& entry);
  void AppendDocumentNavigation(const std::string& url,
                                std::int32_t status_code,
                                const std::string& content_type,
                                const StringMap& response_headers = {},
                                std::int64_t size = 0,
                                const std::string& start_time = std::string(),
                                std::int32_t duration = 0);
  void Clear();
  bool Select(std::size_t index);
  std::optional<TrafficEntry> GetSelected() const;
  std::optional<std::size_t> SelectedIndex() const;
  void LoadJson(const std::string& json);
  std::string ToJson() const;
  std::string GetSelectedJson() const;
  std::string EntryToJson(const TrafficEntry& entry) const;
  std::string ToSummaryJson(const std::optional<std::string>& method = std::nullopt,
                            const std::optional<std::string>& category = std::nullopt,
                            const std::optional<std::string>& status_range = std::nullopt,
                            const std::optional<std::string>& url_pattern = std::nullopt) const;
  std::int32_t Count() const;

 private:
  static constexpr std::size_t kMaxEntries = 2000;

  static std::string CategoryForContentType(const std::string& content_type);
  static bool MatchesStatusRange(std::int32_t status_code, const std::optional<std::string>& range);
  static std::string NormalizeMethod(const std::string& method);
  void ClampAfterTrimLocked(std::size_t removed_count);

  std::vector<TrafficEntry> entries_;
  std::optional<std::size_t> selected_index_;
  mutable std::mutex mutex_;
};

}  // namespace mollotov
