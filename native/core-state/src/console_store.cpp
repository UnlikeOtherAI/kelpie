#include "mollotov/console_store.h"

#include <algorithm>

#include <nlohmann/json.hpp>

#include "store_support.h"

namespace mollotov {
namespace {

using json = nlohmann::json;

json EntryToJsonObject(const ConsoleEntry& entry) {
  json output = {
      {"id", entry.id},
      {"level", ConsoleStore::LevelToString(entry.level)},
      {"text", entry.text},
      {"source", entry.source},
      {"line", entry.line},
      {"column", entry.column},
      {"timestamp", entry.timestamp},
  };
  if (entry.stack_trace.has_value()) {
    output["stack_trace"] = *entry.stack_trace;
  } else {
    output["stack_trace"] = nullptr;
  }
  return output;
}

}  // namespace

void ConsoleStore::Append(const ConsoleEntry& entry) {
  std::lock_guard<std::mutex> lock(mutex_);

  ConsoleEntry normalized = entry;
  if (normalized.id.empty()) {
    normalized.id = store_support::GenerateUuidV4();
  }
  if (normalized.timestamp.empty()) {
    normalized.timestamp = store_support::CurrentIso8601Utc();
  }
  normalized.line = std::max<std::int32_t>(0, normalized.line);
  normalized.column = std::max<std::int32_t>(0, normalized.column);

  entries_.push_back(std::move(normalized));
  if (entries_.size() > kMaxEntries) {
    entries_.erase(entries_.begin(), entries_.begin() + static_cast<long>(entries_.size() - kMaxEntries));
  }
}

void ConsoleStore::Clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  entries_.clear();
}

void ConsoleStore::LoadJson(const std::string& json_text) {
  const json parsed = store_support::ParseJson(json_text);

  std::vector<ConsoleEntry> loaded;
  if (parsed.is_array()) {
    for (const auto& item : parsed) {
      if (!item.is_object()) {
        continue;
      }
      const std::optional<ConsoleLevel> level =
          LevelFromString(store_support::StringOrDefault(item, {"level"}));
      if (!level.has_value()) {
        continue;
      }
      loaded.push_back(ConsoleEntry{
          store_support::StringOrDefault(item, {"id"}, store_support::GenerateUuidV4()),
          *level,
          store_support::StringOrDefault(item, {"text"}),
          store_support::StringOrDefault(item, {"source"}),
          std::max<std::int32_t>(0, store_support::IntOrDefault(item, {"line"})),
          std::max<std::int32_t>(0, store_support::IntOrDefault(item, {"column"})),
          store_support::StringOrDefault(item, {"timestamp"},
                                         store_support::CurrentIso8601Utc()),
          store_support::OptionalValue<std::string>(item, "stack_trace"),
      });
    }
  }

  if (loaded.size() > kMaxEntries) {
    loaded.erase(loaded.begin(), loaded.begin() + static_cast<long>(loaded.size() - kMaxEntries));
  }

  std::lock_guard<std::mutex> lock(mutex_);
  entries_ = std::move(loaded);
}

std::string ConsoleStore::ToJson(const std::optional<std::string>& level_filter) const {
  json output = json::array();
  const std::optional<ConsoleLevel> filter =
      level_filter.has_value() ? LevelFromString(*level_filter) : std::nullopt;

  std::lock_guard<std::mutex> lock(mutex_);
  for (const ConsoleEntry& entry : entries_) {
    if (filter.has_value() && entry.level != *filter) {
      continue;
    }
    output.push_back(EntryToJsonObject(entry));
  }
  return output.dump();
}

std::string ConsoleStore::GetErrorsOnly() const {
  return ToJson(std::string("error"));
}

std::int32_t ConsoleStore::Count() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return static_cast<std::int32_t>(entries_.size());
}

std::optional<ConsoleLevel> ConsoleStore::LevelFromString(const std::string& value) {
  const std::string normalized = store_support::Lowercase(value);
  if (normalized == "log") {
    return ConsoleLevel::kLog;
  }
  if (normalized == "warn") {
    return ConsoleLevel::kWarn;
  }
  if (normalized == "error") {
    return ConsoleLevel::kError;
  }
  if (normalized == "info") {
    return ConsoleLevel::kInfo;
  }
  if (normalized == "debug") {
    return ConsoleLevel::kDebug;
  }
  return std::nullopt;
}

const char* ConsoleStore::LevelToString(ConsoleLevel level) {
  switch (level) {
    case ConsoleLevel::kLog:
      return "log";
    case ConsoleLevel::kWarn:
      return "warn";
    case ConsoleLevel::kError:
      return "error";
    case ConsoleLevel::kInfo:
      return "info";
    case ConsoleLevel::kDebug:
      return "debug";
  }
  return "log";
}

}  // namespace mollotov
