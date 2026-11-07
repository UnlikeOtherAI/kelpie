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
// - removes an empty query string (? with no parameters)
// - removes an empty fragment (# with no value)
// - removes the single implicit root slash from origin-only HTTP(S) URLs
//
// The original URL is always preserved; this function is only used for
// keying dedup lookups so that equivalent URLs collapse correctly.
inline std::string NormalizeUrl(std::string_view url) {
  if (url.empty()) {
    return std::string();
  }

  std::string_view base = url;
  std::string_view query;
  std::string_view fragment;

  size_t fragment_pos = base.find('#');
  if (fragment_pos != std::string_view::npos) {
    fragment = base.substr(fragment_pos);
    base = base.substr(0, fragment_pos);
  }

  size_t query_pos = base.find('?');
  if (query_pos != std::string_view::npos) {
    query = base.substr(query_pos);
    base = base.substr(0, query_pos);
  }

  // Only collapse the implicit root slash on bare HTTP(S) origins:
  // https://example.com/ -> https://example.com
  // Do not rewrite resource paths such as /docs/ because trailing slash can
  // change the resource identity on real servers.
  const size_t scheme_pos = base.find("://");
  if (scheme_pos != std::string_view::npos &&
      (base.substr(0, scheme_pos) == "http" || base.substr(0, scheme_pos) == "https")) {
    const size_t authority_start = scheme_pos + 3;
    const size_t slash_pos = base.find('/', authority_start);
    if (slash_pos != std::string_view::npos && slash_pos == base.length() - 1) {
      base.remove_suffix(1);
    }
  }

  std::string result;
  result.reserve(base.length() + (query.length() > 1 ? query.length() : 0) +
                 (fragment.length() > 1 ? fragment.length() : 0));
  result.append(base);

  if (query.length() > 1) {  // Not just '?'
    result.append(query);
  }
  if (fragment.length() > 1) {  // Not just '#'
    result.append(fragment);
  }

  return result;
}

}  // namespace kelpie::store_support
