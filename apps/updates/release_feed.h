#pragma once

#include <algorithm>
#include <array>
#include <optional>
#include <regex>
#include <string>
#include <nlohmann/json.hpp>

namespace kelpie::updates {
inline constexpr char kFeedURL[] =
    "https://api.github.com/repos/UnlikeOtherAI/kelpie/releases?per_page=100";
inline constexpr char kMarker[] = "<!-- kelpie-update: ";
struct Release { std::string version, url, sha256; };

inline std::optional<std::array<int, 3>> Version(const std::string& text) {
  static const std::regex pattern(R"(^([0-9]{1,6})\.([0-9]{1,6})\.([0-9]{1,6})$)");
  std::smatch match;
  if (!std::regex_match(text, match, pattern)) return std::nullopt;
  return std::array<int, 3>{std::stoi(match[1]), std::stoi(match[2]), std::stoi(match[3])};
}

inline bool SafeURL(const std::string& url, const std::string& target) {
  if (url.find_first_of("\r\n\t \\") != std::string::npos || url.find("..") != std::string::npos)
    return false;
  const std::string github = "https://github.com/UnlikeOtherAI/kelpie/releases/download/";
  if (url.starts_with(github) && url.size() > github.size() &&
      url.find_first_of("?#%") == std::string::npos) return true;
  if (target == "ios" && std::regex_match(url,
      std::regex(R"(^https://apps\.apple\.com/([a-z]{2}/)?app/([a-zA-Z0-9-]+/)?id[0-9]+$)"))) return true;
  return target == "android" && url == "https://play.google.com/store/apps/details?id=com.kelpie.browser";
}

// A date tag is never an app version. Only ready, explicitly published component
// metadata can produce a prompt; unrelated and still-building releases are ignored.
inline std::optional<Release> FindRelease(const std::string& body,
    const std::string& target, const std::string& current) {
  const auto installed = Version(current);
  const auto feed = nlohmann::json::parse(body, nullptr, false);
  if (!installed || !feed.is_array()) return std::nullopt;
  std::optional<Release> newest;
  for (const auto& entry : feed) {
    if (!entry.is_object() || !entry.contains("draft") || !entry["draft"].is_boolean() ||
        entry["draft"].get<bool>() || !entry.contains("prerelease") ||
        !entry["prerelease"].is_boolean() || entry["prerelease"].get<bool>() ||
        !entry.contains("body") || !entry["body"].is_string()) continue;
    const std::string notes = entry["body"];
    size_t cursor = 0;
    while ((cursor = notes.find(kMarker, cursor)) != std::string::npos) {
      cursor += std::char_traits<char>::length(kMarker);
      const auto end = notes.find(" -->", cursor);
      if (end == std::string::npos) break;
      const auto item = nlohmann::json::parse(notes.substr(cursor, end - cursor), nullptr, false);
      cursor = end + 4;
      if (!item.is_object() || !item.contains("target") || !item["target"].is_string() ||
          item["target"].get<std::string>() != target || !item.contains("version") ||
          !item["version"].is_string() || !item.contains("url") || !item["url"].is_string() ||
          !item.contains("sha256") || !item["sha256"].is_string()) continue;
      Release candidate{item["version"], item["url"], item["sha256"]};
      const auto version = Version(candidate.version);
      if (version && *version > *installed && SafeURL(candidate.url, target) &&
          std::regex_match(candidate.sha256, std::regex("[a-f0-9]{64}")) &&
          (!newest || *version > *Version(newest->version))) newest = candidate;
    }
  }
  return newest;
}
}  // namespace kelpie::updates
