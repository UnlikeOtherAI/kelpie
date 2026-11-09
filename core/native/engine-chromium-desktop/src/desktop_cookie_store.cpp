#include "desktop_cookie_store.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <map>

#include "desktop_cookie_planner.h"

namespace kelpie::desktop_cookie_store {
namespace {

std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}

std::string StringField(const Json& object, const char* key) {
  const auto it = object.find(key);
  return it != object.end() && it->is_string() ? it->get<std::string>() : std::string();
}

bool Partitioned(const Json& cookie) { return cookie.value("partitioned", false) == true; }

bool ValidSameSite(const Json& value) {
  return value.is_string() && (value == "Strict" || value == "Lax" || value == "None" || value == "Unspecified");
}

struct Url {
  bool https = false;
  std::string host;  // lower-case, no brackets or port
  std::string path;  // starts with '/'
};

std::optional<Url> ParseUrl(const std::string& text) {
  const auto scheme = text.find("://");
  if (scheme == std::string::npos) return std::nullopt;
  Url url;
  const std::string protocol = Lower(text.substr(0, scheme));
  if (protocol != "http" && protocol != "https") return std::nullopt;
  url.https = protocol == "https";
  std::string rest = text.substr(scheme + 3);
  rest = rest.substr(0, rest.find_first_of("?#"));
  const auto slash = rest.find('/');
  std::string authority = rest.substr(0, slash);
  url.path = slash == std::string::npos ? "/" : rest.substr(slash);
  if (authority.find('@') != std::string::npos) return std::nullopt;
  if (!authority.empty() && authority.front() == '[') {
    const auto close = authority.find(']');
    if (close == std::string::npos) return std::nullopt;
    url.host = authority.substr(1, close - 1);
  } else {
    url.host = authority.substr(0, authority.find(':'));
  }
  if (url.host.empty()) return std::nullopt;
  url.host = Lower(url.host);
  return url;
}

// Days since 1970-01-01 → civil date (Howard Hinnant's algorithm).
void CivilFromDays(std::int64_t days, std::int64_t* year, unsigned* month, unsigned* day) {
  days += 719468;
  const std::int64_t era = (days >= 0 ? days : days - 146096) / 146097;
  const unsigned doe = static_cast<unsigned>(days - era * 146097);
  const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const unsigned mp = (5 * doy + 2) / 153;
  *day = doy - (153 * mp + 2) / 5 + 1;
  *month = mp < 10 ? mp + 3 : mp - 9;
  *year = static_cast<std::int64_t>(yoe) + era * 400 + (*month <= 2 ? 1 : 0);
}

std::string IsoTime(std::int64_t seconds) {
  const std::int64_t days = seconds >= 0 ? seconds / 86400 : (seconds - 86399) / 86400;
  const std::int64_t rest = seconds - days * 86400;
  std::int64_t year = 0;
  unsigned month = 0, day = 0;
  CivilFromDays(days, &year, &month, &day);
  char buffer[40];
  std::snprintf(buffer, sizeof(buffer), "%04lld-%02u-%02uT%02lld:%02lld:%02lld.000Z", static_cast<long long>(year),
                month, day, static_cast<long long>(rest / 3600), static_cast<long long>(rest / 60 % 60),
                static_cast<long long>(rest % 60));
  return buffer;
}

Json Failure(const Json& cookie, const std::string& error) {
  return {{"name", StringField(cookie, "name")}, {"domain", StringField(cookie, "domain")}, {"error", error}};
}

constexpr const char* kRefused = "rejected by engine";

}  // namespace

std::string BareDomain(std::string domain) {
  domain = Lower(std::move(domain));
  if (!domain.empty() && domain.front() == '.') domain.erase(0, 1);
  return domain;
}

Json Readback(const Json& cookies, const Json& op_cookie) {
  const std::string name = StringField(op_cookie, "name");
  const std::string host = BareDomain(StringField(op_cookie, "domain"));
  Json out = Json::array();
  for (const auto& cookie : cookies) {
    if (Partitioned(cookie)) continue;
    if (StringField(cookie, "name") == name && BareDomain(StringField(cookie, "domain")) == host) out.push_back(cookie);
  }
  return out;
}

bool SyncSnapshot(CookieBackend& backend, Json* cookies, Json* coverage, const Cancelled& cancelled) {
  Json all;
  if (!backend.VisitAll(&all, cancelled) || !all.is_array()) return false;
  *cookies = Json::array();
  for (auto& cookie : all) {
    if (!Partitioned(cookie)) cookies->push_back(std::move(cookie));
  }
  *coverage = {{"all", true}};  // a full-store enumeration
  return true;
}

std::optional<Json> ApplySyncOps(CookieBackend& backend, const Json& ops, const Cancelled& cancelled) {
  if (!ops.is_array()) return std::nullopt;
  // Round r holds the r-th op of every (bare domain, name) group.
  std::map<std::string, std::size_t> seen;
  std::vector<std::vector<std::size_t>> rounds;
  for (std::size_t i = 0; i < ops.size(); ++i) {
    const Json& cookie = ops[i].value("cookie", Json::object());
    const std::string group = BareDomain(StringField(cookie, "domain")) + '\0' + StringField(cookie, "name");
    const std::size_t round = seen[group]++;
    if (rounds.size() <= round) rounds.resize(round + 1);
    rounds[round].push_back(i);
  }
  std::vector<Json> results(ops.size());
  for (const auto& round : rounds) {
    if (cancelled && cancelled()) return std::nullopt;
    std::vector<CookieBackend::Write> writes;
    for (const std::size_t index : round) {
      writes.push_back({ops[index].value("cookie", Json::object()), ops[index].value("op", std::string()) == "delete"});
    }
    const auto flags = backend.Apply(writes, cancelled);
    if (!flags || flags->size() != writes.size()) return std::nullopt;
    Json after;
    if (!backend.VisitAll(&after, cancelled) || !after.is_array()) return std::nullopt;  // never invent a read-back
    for (std::size_t k = 0; k < round.size(); ++k) {
      const Json& op = ops[round[k]];
      results[round[k]] = {{"id", op.value("id", Json())}, {"ok", (*flags)[k]},
                           {"readback", Readback(after, writes[k].cookie)}};
    }
  }
  return Json(results);
}

Json ToAutomation(const Json& wire) {
  const Json& expires = wire.value("expires", Json());
  return {{"name", StringField(wire, "name")},
          {"value", StringField(wire, "value")},
          {"domain", StringField(wire, "domain")},
          {"path", wire.value("path", std::string("/"))},
          {"expires", expires.is_number_integer() ? Json(IsoTime(expires.get<std::int64_t>())) : Json(nullptr)},
          {"httpOnly", wire.value("httpOnly", false)},
          {"secure", wire.value("secure", false)},
          {"sameSite", wire.value("sameSite", std::string("Unspecified"))}};
}

ParsedCookie FromAutomation(const Json& input) {
  if (!input.is_object()) return {std::nullopt, "a cookie must be an object"};
  for (const char* key : {"name", "value", "domain", "path", "expires", "httpOnly", "secure", "sameSite"}) {
    if (!input.contains(key)) return {std::nullopt, std::string(key) + " is required"};
  }
  if (!input["name"].is_string() || input["name"].get<std::string>().empty()) {
    return {std::nullopt, "name must be a non-empty string"};
  }
  if (!input["value"].is_string()) return {std::nullopt, "value must be a string"};
  if (!input["httpOnly"].is_boolean() || !input["secure"].is_boolean()) {
    return {std::nullopt, "httpOnly and secure must be booleans"};
  }
  if (!ValidSameSite(input["sameSite"])) return {std::nullopt, "sameSite must be Strict, Lax, None or Unspecified"};
  const std::string domain = input["domain"].is_string() ? Lower(input["domain"].get<std::string>()) : std::string();
  if (BareDomain(domain).empty() || domain.find_first_of("/\\ ?#@;,") != std::string::npos) {
    return {std::nullopt, "domain must be a host, with a leading dot for a domain cookie"};
  }
  if (!input["path"].is_string() || input["path"].get<std::string>().empty() ||
      input["path"].get<std::string>().front() != '/') {
    return {std::nullopt, "path must start with /"};
  }
  Json expires = nullptr;
  if (!input["expires"].is_null()) {
    const auto seconds = input["expires"].is_string() ? desktop_cookie::ParseExpirySeconds(input["expires"])
                                                      : std::nullopt;
    if (!seconds || *seconds < 0 || *seconds > 253402300799.0) {
      return {std::nullopt, "expires must be ISO-8601 UTC or null"};
    }
    expires = static_cast<std::int64_t>(std::floor(*seconds));
  }
  const std::string& name = input["name"].get_ref<const std::string&>();
  const std::string& value = input["value"].get_ref<const std::string&>();
  if (name.size() + value.size() > 4096) return {std::nullopt, "name and value exceed 4096 bytes"};
  return {Json{{"domain", domain}, {"path", input["path"]}, {"name", name}, {"value", value}, {"expires", expires},
               {"secure", input["secure"]}, {"httpOnly", input["httpOnly"]}, {"sameSite", input["sameSite"]}},
          ""};
}

std::optional<bool> MatchesUrl(const Json& cookie, const std::string& text) {
  const auto url = ParseUrl(text);
  if (!url) return std::nullopt;
  const std::string domain = Lower(StringField(cookie, "domain"));
  const bool domain_cookie = !domain.empty() && domain.front() == '.';
  const std::string host = BareDomain(domain);
  const bool host_match = domain_cookie ? DomainMatches(url->host, host) : url->host == host;
  std::string path = cookie.value("path", std::string("/"));
  if (path.empty()) path = "/";
  const bool path_match = url->path == path ||
                          (url->path.rfind(path, 0) == 0 && (path.back() == '/' || url->path[path.size()] == '/'));
  return host_match && path_match && (!cookie.value("secure", false) || url->https);
}

bool DomainMatches(const std::string& cookie_domain, const std::string& filter) {
  const std::string host = BareDomain(cookie_domain);
  const std::string wanted = BareDomain(filter);
  if (wanted.empty()) return false;
  return host == wanted ||
         (host.size() > wanted.size() && host.compare(host.size() - wanted.size(), wanted.size(), wanted) == 0 &&
          host[host.size() - wanted.size() - 1] == '.');
}

Json Filter(const Json& automation_cookies, const std::optional<std::string>& domain,
            const std::optional<std::string>& name, const std::optional<std::string>& url) {
  Json out = Json::array();
  for (const auto& cookie : automation_cookies) {
    if (domain && !DomainMatches(StringField(cookie, "domain"), *domain)) continue;
    if (name && StringField(cookie, "name") != *name) continue;
    if (url && !MatchesUrl(cookie, *url).value_or(false)) continue;
    out.push_back(cookie);
  }
  return out;
}

std::optional<std::vector<Json>> ParseCookies(const Json& inputs, std::string* error) {
  std::vector<Json> cookies;
  for (std::size_t i = 0; i < inputs.size(); ++i) {
    auto parsed = FromAutomation(inputs[i]);
    if (!parsed.wire) {
      *error = "cookies[" + std::to_string(i) + "]: " + parsed.error;
      return std::nullopt;
    }
    cookies.push_back(std::move(*parsed.wire));
  }
  return cookies;
}

Json WriteCookies(CookieBackend& backend, const std::vector<Json>& cookies, const Cancelled& cancelled) {
  std::vector<CookieBackend::Write> writes;
  for (const auto& cookie : cookies) writes.push_back({cookie, false});
  const auto flags = backend.Apply(writes, cancelled);
  Json failed = Json::array();
  std::size_t set = 0;
  for (std::size_t i = 0; i < cookies.size(); ++i) {
    if (flags && i < flags->size() && (*flags)[i]) {
      ++set;
      continue;
    }
    Json failure = Failure(cookies[i], kRefused);
    failure["index"] = i;
    failed.push_back(std::move(failure));
  }
  return {{"set", set}, {"failed", failed}};
}

std::optional<Json> CopyCookies(CookieBackend& from, CookieBackend& to, const std::optional<std::string>& domain,
                                const Cancelled& cancelled) {
  Json all;
  if (!from.VisitAll(&all, cancelled) || !all.is_array()) return std::nullopt;
  std::vector<CookieBackend::Write> writes;
  for (const auto& cookie : all) {
    if (Partitioned(cookie)) continue;
    if (domain && !DomainMatches(StringField(cookie, "domain"), *domain)) continue;
    writes.push_back({cookie, false});
  }
  Json failed = Json::array();
  std::size_t copied = 0;
  if (!writes.empty()) {
    const auto flags = to.Apply(writes, cancelled);
    for (std::size_t k = 0; k < writes.size(); ++k) {
      if (flags && k < flags->size() && (*flags)[k]) {
        ++copied;
      } else {
        failed.push_back(Failure(writes[k].cookie, kRefused));
      }
    }
  }
  return Json{{"copied", copied}, {"failed", failed}};
}

}  // namespace kelpie::desktop_cookie_store
