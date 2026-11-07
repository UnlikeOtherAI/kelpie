#include "desktop_cookie_planner.h"

#include <cmath>
#include <cstdint>
#include <regex>

namespace kelpie::desktop_cookie {
namespace {

bool IsString(const Json& object, const char* key, bool allow_empty = true) {
  const auto value = object.find(key);
  return value == object.end() || (value->is_string() && (allow_empty || !value->get<std::string>().empty()));
}

bool IsBoolean(const Json& object, const char* key) {
  const auto value = object.find(key);
  return value == object.end() || value->is_boolean();
}

bool IsLeapYear(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }

int DaysInMonth(int year, int month) {
  static constexpr int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  return month == 2 && IsLeapYear(year) ? 29 : days[month - 1];
}

// Days since Unix epoch. The caller has already checked the civil date.
std::int64_t DaysFromCivil(int year, unsigned month, unsigned day) {
  year -= month <= 2;
  const int era = (year >= 0 ? year : year - 399) / 400;
  const unsigned yoe = static_cast<unsigned>(year - era * 400);
  const unsigned doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return static_cast<std::int64_t>(era) * 146097 + static_cast<int>(doe) - 719468;
}

bool ValidSameSite(const std::string& value) {
  return value == "Lax" || value == "Strict" || value == "None";
}

}  // namespace

std::optional<double> ParseExpirySeconds(const Json& value) {
  if (value.is_number()) {
    const double seconds = value.get<double>();
    return std::isfinite(seconds) ? std::optional<double>(seconds) : std::nullopt;
  }
  if (!value.is_string()) return std::nullopt;
  static const std::regex pattern(R"(^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.(\d{1,9}))?Z$)");
  std::smatch match;
  const std::string text = value.get<std::string>();
  if (!std::regex_match(text, match, pattern)) return std::nullopt;
  const int year = std::stoi(match[1].str());
  const int month = std::stoi(match[2].str());
  const int day = std::stoi(match[3].str());
  const int hour = std::stoi(match[4].str());
  const int minute = std::stoi(match[5].str());
  const int second = std::stoi(match[6].str());
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > DaysInMonth(year, month) ||
      hour > 23 || minute > 59 || second > 59) return std::nullopt;
  double result = static_cast<double>(DaysFromCivil(year, static_cast<unsigned>(month), static_cast<unsigned>(day)) * 86400 +
                                      hour * 3600 + minute * 60 + second);
  if (match[8].matched) result += std::stod("0." + match[8].str());
  return result;
}

Plan PlanSetCookie(const Json& request) {
  if (!request.is_object()) return {false, "Cookie must be an object"};
  Json params = request;
  for (const char* key : {"tabId", "generation", "timeout"}) params.erase(key);
  if (!IsString(params, "name", false) || !IsString(params, "value") || !IsString(params, "url", false) ||
      !IsString(params, "domain", false) || !IsString(params, "path") || !IsBoolean(params, "httpOnly") ||
      !IsBoolean(params, "secure")) return {false, "Cookie has an invalid field type"};
  if (!params.contains("name") || (!params.contains("url") && !params.contains("domain"))) {
    return {false, "Cookies require a non-empty name and url or domain"};
  }
  if (params.contains("sameSite")) {
    if (!params["sameSite"].is_string() || !ValidSameSite(params["sameSite"].get<std::string>())) {
      return {false, "sameSite must be Strict, Lax, or None"};
    }
  }
  if (params.contains("expires")) {
    const auto expiry = ParseExpirySeconds(params["expires"]);
    if (!expiry) return {false, "expires must be finite epoch seconds or RFC 3339 UTC"};
    params["expires"] = *expiry;
  }
  return {true, {}, std::move(params)};
}

DeletePlan PlanDeleteCookies(const Json& request) {
  if (!request.is_object()) return {false, "Cookie deletion must be an object"};
  const auto all = request.find("deleteAll");
  if (all != request.end() && !all->is_boolean()) return {false, "deleteAll must be a boolean"};
  if (all != request.end() && all->get<bool>()) return {true, {}, DeletePlan::Action::kClearAll, Json::object()};
  for (const char* unsupported : {"url", "path"}) {
    if (request.contains(unsupported)) return {false, std::string(unsupported) + " is not supported for cookie deletion"};
  }
  Json params = Json::object();
  for (const char* selector : {"name", "domain"}) {
    const auto value = request.find(selector);
    if (value == request.end()) continue;
    if (!value->is_string() || value->get<std::string>().empty()) {
      return {false, std::string(selector) + " must be a non-empty string"};
    }
    params[selector] = *value;
  }
  if (params.empty()) return {false, "Cookie deletion requires name, domain, or deleteAll"};
  return {true, {}, DeletePlan::Action::kDelete, std::move(params)};
}

Plan PlanGetCookies(const Json& query) {
  if (!query.is_object()) return {false, "Cookie query must be an object"};
  for (const char* selector : {"name", "domain", "url"}) {
    const auto value = query.find(selector);
    if (value != query.end() && (!value->is_string() || value->get<std::string>().empty())) {
      return {false, std::string(selector) + " must be a non-empty string"};
    }
  }
  const auto url = query.find("url");
  return url == query.end() ? Plan{true, {}, Json::object()} : Plan{true, {}, {{"urls", Json::array({*url})}}};
}

bool MatchesFilter(const Json& cookie, const Json& query) {
  if (!cookie.is_object() || !query.is_object()) return false;
  for (const char* selector : {"name", "domain"}) {
    const auto wanted = query.find(selector);
    if (wanted == query.end()) continue;
    const auto actual = cookie.find(selector);
    if (actual == cookie.end() || !actual->is_string() || *actual != *wanted) return false;
  }
  return true;
}

}  // namespace kelpie::desktop_cookie
