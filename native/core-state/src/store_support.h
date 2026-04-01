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

namespace mollotov::store_support {

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

  std::array<int, 16> bytes{};
  {
    std::lock_guard<std::mutex> lock(random_mutex);
    for (int& byte : bytes) {
      byte = nibble(generator);
    }
    bytes[6] = 4;
    bytes[8] = variant(generator);
  }

  std::ostringstream stream;
  for (std::size_t index = 0; index < bytes.size(); ++index) {
    if (index == 4 || index == 6 || index == 8 || index == 10) {
      stream << '-';
    }
    stream << std::hex << std::nouppercase << bytes[index];
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

}  // namespace mollotov::store_support
