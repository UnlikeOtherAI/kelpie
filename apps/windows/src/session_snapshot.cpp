#include "session_snapshot.h"

#include "kelpie/partition.h"

#include <charconv>
#include <limits>
#include <string_view>
#include <unordered_set>

namespace kelpie::windows {
namespace {

bool ReadUnsigned(const nlohmann::json& value, std::uint64_t* output) {
  if (output == nullptr) return false;
  if (value.is_number_unsigned()) {
    *output = value.get<std::uint64_t>();
    return true;
  }
  if (!value.is_number_integer()) return false;
  const auto signed_value = value.get<std::int64_t>();
  if (signed_value < 0) return false;
  *output = static_cast<std::uint64_t>(signed_value);
  return true;
}

bool TabNumber(const std::string& id, std::uint64_t* number) {
  constexpr std::string_view prefix = "tab-";
  if (number == nullptr || id.size() <= prefix.size() || id.rfind(prefix, 0) != 0) return false;
  const std::string_view digits{id.data() + prefix.size(), id.size() - prefix.size()};
  if (digits.front() == '0') return false;
  std::uint64_t parsed = 0;
  const auto result = std::from_chars(digits.data(), digits.data() + digits.size(), parsed);
  if (result.ec != std::errc{} || result.ptr != digits.data() + digits.size() || parsed == 0) return false;
  *number = parsed;
  return true;
}

bool IsRestorableUrl(const std::string& url) {
  return url.rfind("https://", 0) == 0 || url.rfind("http://", 0) == 0 ||
      url.rfind("about:", 0) == 0 || url.rfind("data:", 0) == 0;
}

// The partition fields are optional, but a present one has to be well formed.
// A snapshot naming a partition the engine would reject is corrupt, and
// silently dropping the field would restore an isolated tab into the shared
// store — the one failure mode this feature must never have.
bool ReadPartitionFields(const nlohmann::json& item, SessionTab* tab) {
  if (item.contains("name")) {
    const auto& name = item.at("name");
    if (!name.is_string() || name.get<std::string>().size() > kelpie::kMaxTabNameLength) return false;
    tab->name = name.get<std::string>();
  }
  const bool has_partition = item.contains("partition");
  if (has_partition) {
    const auto& partition = item.at("partition");
    if (!partition.is_string() || !kelpie::IsValidPartition(partition.get<std::string>())) return false;
    tab->partition = partition.get<std::string>();
  }
  if (!item.contains("persistent")) return true;
  const auto& persistent = item.at("persistent");
  if (!persistent.is_boolean() || !has_partition) return false;
  tab->persistent = persistent.get<bool>();
  return true;
}

}  // namespace

bool ParseSessionSnapshot(const nlohmann::json& value, SessionSnapshot* output) {
  if (output == nullptr || !value.is_object() || !value.contains("version") ||
      !value.at("version").is_number_integer() || value.at("version") != 1 ||
      !value.contains("epoch") || !value.contains("nextTabId") ||
      !value.contains("tabs") || !value.at("tabs").is_array()) {
    return false;
  }

  SessionSnapshot parsed;
  if (!ReadUnsigned(value.at("epoch"), &parsed.epoch) ||
      !ReadUnsigned(value.at("nextTabId"), &parsed.next_tab_id) ||
      parsed.next_tab_id == 0 || parsed.next_tab_id == std::numeric_limits<std::uint64_t>::max()) {
    return false;
  }

  std::unordered_set<std::string> ids;
  bool has_active = false;
  std::uint64_t highest_id = 0;
  for (const auto& item : value.at("tabs")) {
    if (!item.is_object() || !item.contains("id") || !item.at("id").is_string() ||
        !item.contains("url") || !item.at("url").is_string() ||
        !item.contains("active") || !item.at("active").is_boolean()) {
      return false;
    }
    SessionTab tab{item.at("id").get<std::string>(), item.at("url").get<std::string>(),
                   item.at("active").get<bool>()};
    std::uint64_t id_number = 0;
    if (!TabNumber(tab.id, &id_number) || !IsRestorableUrl(tab.url) ||
        !ids.insert(tab.id).second || (tab.active && has_active) ||
        !ReadPartitionFields(item, &tab)) {
      return false;
    }
    highest_id = std::max(highest_id, id_number);
    has_active = has_active || tab.active;
    parsed.tabs.push_back(std::move(tab));
  }

  if (parsed.tabs.empty() || parsed.next_tab_id <= highest_id) return false;
  // Older profiles did not record a selected tab. Their first tab is retained
  // as the explicit selected tab, so restoration remains deterministic.
  if (!has_active) parsed.tabs.front().active = true;
  *output = std::move(parsed);
  return true;
}

nlohmann::json SerializeSessionSnapshot(const SessionSnapshot& snapshot) {
  nlohmann::json tabs = nlohmann::json::array();
  for (const auto& tab : snapshot.tabs) {
    nlohmann::json entry = {{"id", tab.id}, {"url", tab.url}, {"active", tab.active}};
    // Absent rather than null for an ordinary tab, so a profile that never
    // used a partition keeps exactly the file it had before.
    if (tab.name) entry["name"] = *tab.name;
    if (tab.partition) {
      entry["partition"] = *tab.partition;
      entry["persistent"] = tab.persistent;
    }
    tabs.push_back(std::move(entry));
  }
  return {{"version", 1}, {"epoch", snapshot.epoch}, {"nextTabId", snapshot.next_tab_id},
          {"tabs", std::move(tabs)}};
}

}  // namespace kelpie::windows
