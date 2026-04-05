#pragma once

#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace kelpie {

enum class ConsoleLevel {
  kLog = 0,
  kWarn,
  kError,
  kInfo,
  kDebug,
};

struct ConsoleEntry {
  std::string id;
  ConsoleLevel level = ConsoleLevel::kLog;
  std::string text;
  std::string source;
  std::int32_t line = 0;
  std::int32_t column = 0;
  std::string timestamp;
  std::optional<std::string> stack_trace;
};

class ConsoleStore {
 public:
  void Append(const ConsoleEntry& entry);
  void Clear();
  void LoadJson(const std::string& json);
  std::string ToJson(const std::optional<std::string>& level_filter = std::nullopt) const;
  std::string GetErrorsOnly() const;
  std::int32_t Count() const;

  static std::optional<ConsoleLevel> LevelFromString(const std::string& value);
  static const char* LevelToString(ConsoleLevel level);

 private:
  static constexpr std::size_t kMaxEntries = 1000;

  std::vector<ConsoleEntry> entries_;
  mutable std::mutex mutex_;
};

}  // namespace kelpie
