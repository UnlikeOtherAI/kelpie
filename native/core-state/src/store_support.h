#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <chrono>
#include <cctype>
#include <ctime>
#include <iomanip>
#include <initializer_list>
#include <mutex>
#include <optional>
#include <random>
#include <sstream>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

namespace kelpie::store_support {

using json = nlohmann::json;

inline std::string Trim(std::string_view value) {
  const auto* begin = value.data();
  const auto* end = begin + value.size();
  while (begin < end && std::isspace(static_cast<unsigned char>(*begin)) != 0) {
    ++begin;
  }
  while (end > begin && std::isspace(static_cast<unsigned char>(*(end - 1))) != 0) {
    --end;
  }
  return std::string(begin, end);
}

inline std::string Lowercase(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

inline std::string CurrentIso8601Utc() {
  const auto now = std::chrono::system_clock::now();
  const auto seconds = std::chrono::system_clock::to_time_t(now);

  std::tm utc_tm{};
  {
    static std::mutex gmtime_mutex;
    std::lock_guard<std::mutex> lock(gmtime_mutex);
    const std::tm* value = std::gmtime(&seconds);
    if (value != nullptr) {
      utc_tm = *value;
    }
  }

  std::ostringstream stream;
  stream << std::put_time(&utc_tm, "%Y-%m-%dT%H:%M:%SZ");
  return stream.str();
}

inline std::string GenerateUuidV4() {
  static std::random_device device;
  static std::mutex random_mutex;
  static std::mt19937 generator(device());
  std::uniform_int_distribution<int> nibble(0, 15);
  std::uniform_int_distribution<int> variant(8, 11);

  std::array<int, 32> nibbles{};
  {
    std::lock_guard<std::mutex> lock(random_mutex);
    for (int& n : nibbles) {
      n = nibble(generator);
    }
    nibbles[12] = 4;
    nibbles[16] = variant(generator);
  }

  std::ostringstream stream;
  for (std::size_t index = 0; index < nibbles.size(); ++index) {
    if (index == 8 || index == 12 || index == 16 || index == 20) {
      stream << '-';
    }
    stream << std::hex << std::nouppercase << nibbles[index];
  }
  return stream.str();
}

inline json ParseJson(const std::string& text) {
  return json::parse(text, nullptr, false);
}

inline std::string StringOrDefault(const json& object,
                                   std::initializer_list<const char*> keys,
                                   const std::string& fallback = std::string()) {
  for (const char* key : keys) {
    const auto it = object.find(key);
    if (it != object.end() && it->is_string()) {
      return it->get<std::string>();
    }
  }
  return fallback;
}

inline std::int32_t IntOrDefault(const json& object,
                                 std::initializer_list<const char*> keys,
                                 std::int32_t fallback = 0) {
  for (const char* key : keys) {
    const auto it = object.find(key);
    if (it != object.end() && it->is_number_integer()) {
      return it->get<std::int32_t>();
    }
  }
  return fallback;
}

inline std::int64_t Int64OrDefault(const json& object,
                                   std::initializer_list<const char*> keys,
                                   std::int64_t fallback = 0) {
  for (const char* key : keys) {
    const auto it = object.find(key);
    if (it != object.end() && it->is_number_integer()) {
      return it->get<std::int64_t>();
    }
  }
  return fallback;
}

template <typename T>
inline std::optional<T> OptionalValue(const json& object, const char* key) {
  const auto it = object.find(key);
  if (it == object.end() || it->is_null()) {
    return std::nullopt;
  }
  return it->get<T>();
}

// Normalizes a URL for equality comparison used in dedup.
//
// Applies only safe, lossless transformations:
// - strips a trailing slash from the path (unless the path is "/" alone)
// - removes an empty query string (? with no parameters)
// - removes an empty fragment (# with no value)
//
// The original URL is always preserved; this function is only used for
// keying dedup lookups so that equivalent URLs collapse correctly.
inline std::string NormalizeUrl(std::string_view url) {
  if (url.empty()) {
    return std::string();
  }

  // Find the first '?' or '#' to split base from query/fragment.
  std::size_t sep = std::string_view::npos;
  std::size_t query_pos = url.find('?');
  std::size_t fragment_pos = url.find('#');
  if (query_pos != std::string_view::npos && fragment_pos != std::string_view::npos) {
    sep = std::min(query_pos, fragment_pos);
  } else if (query_pos != std::string_view::npos) {
    sep = query_pos;
  } else {
    sep = fragment_pos;
  }

  std::string result;
  if (sep == std::string_view::npos) {
    // No query or fragment — normalize in-place.
    result.assign(url);
  } else {
    result.assign(url.substr(0, sep));
  }

  // Strip trailing slash only if there is content before it.
  // This keeps "https://host/" as "https://host" but leaves "/" as "/".
  if (result.size() >= 2 && result.back() == '/') {
    bool has_content_before = false;
    for (std::size_t i = 0; i < result.size() - 1; ++i) {
      if (result[i] != '/') {
        has_content_before = true;
        break;
      }
    }
    if (has_content_before) {
      result.pop_back();
    }
  }

  if (sep == std::string_view::npos) {
    return result;
  }

  // Walk the query/fragment portion, building non-empty components.
  std::string query_part;
  std::string fragment_part;
  std::size_t i = 0;

  while (i < url.size()) {
    if (url[i] == '?') {
      std::size_t end = url.find('#', i + 1);
      if (end == std::string_view::npos) {
        end = url.size();
      }
      if (end > i + 1) {
        query_part.assign(url.data() + i, end - i);
      }
      i = end;
    } else if (url[i] == '#') {
      if (url.size() > i + 1) {
        fragment_part.assign(url.data() + i, url.size() - i);
      }
      break;
    } else {
      ++i;
    }
  }

  result.append(query_part);
  result.append(fragment_part);
  return result;
}

}  // namespace kelpie::store_support
