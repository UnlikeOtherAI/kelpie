#include "session_snapshot.h"

#include "kelpie/internal_scheme.h"

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
  // `kelpie://` is Kelpie's own first-party scheme. Without it a restored
  // session would silently drop every start page tab.
  return url.rfind("https://", 0) == 0 || url.rfind("http://", 0) == 0 ||
      url.rfind("about:", 0) == 0 || url.rfind("data:", 0) == 0 ||
      IsInternalSchemeUrl(url);
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
        !ids.insert(tab.id).second || (tab.active && has_active)) {
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
    tabs.push_back({{"id", tab.id}, {"url", tab.url}, {"active", tab.active}});
  }
  return {{"version", 1}, {"epoch", snapshot.epoch}, {"nextTabId", snapshot.next_tab_id},
          {"tabs", std::move(tabs)}};
}

}  // namespace kelpie::windows
