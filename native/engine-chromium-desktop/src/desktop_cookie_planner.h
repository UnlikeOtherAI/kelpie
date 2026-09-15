#pragma once

#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie::desktop_cookie {

using Json = nlohmann::json;

struct Plan {
  bool ok = false;
  std::string error;
  Json params = Json::object();
};

struct DeletePlan {
  enum class Action { kDelete, kClearAll };
  bool ok = false;
  std::string error;
  Action action = Action::kDelete;
  Json params = Json::object();
};

// Returns CDP Network.setCookie parameters after removing only the handler's
// transport fields. It never coerces malformed cookie data.
Plan PlanSetCookie(const Json& request);

// A delete selector is either deleteAll:true, a non-empty name, or a non-empty
// domain. CDP returns no deletion count, so callers must return its response
// rather than inventing one.
DeletePlan PlanDeleteCookies(const Json& request);

// Strict RFC 3339 UTC parser used for Network.setCookie expires. Fractional
// seconds are retained; impossible calendar dates are rejected.
std::optional<double> ParseExpirySeconds(const Json& value);

// Uses Chromium's Network.getCookies URL matching whenever a URL is supplied.
// The returned parameters target either Network.getCookies or getAllCookies.
Plan PlanGetCookies(const Json& query);

// Filters only the selectors Chromium does not apply to URL-scoped results.
bool MatchesFilter(const Json& cookie, const Json& query);

}  // namespace kelpie::desktop_cookie
