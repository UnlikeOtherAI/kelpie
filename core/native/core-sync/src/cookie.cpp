#include "cookie.h"

#include <algorithm>
#include <cctype>

#include "sha256.h"

namespace kelpie::sync {
namespace {

std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}

bool IsLoopbackHost(const std::string& host) {
  if (host == "localhost" || host == "::1" || host == "[::1]") return true;
  if (host.size() > 10 && host.compare(host.size() - 10, 10, ".localhost") == 0) return true;
  if (host.rfind("127.", 0) == 0) {
    return std::all_of(host.begin(), host.end(),
                       [](char c) { return c == '.' || std::isdigit(static_cast<unsigned char>(c)); });
  }
  return false;
}

std::optional<std::string> CanonicalSameSite(const nlohmann::json& value) {
  if (!value.is_string()) return std::nullopt;
  const std::string lowered = Lower(value.get<std::string>());
  if (lowered == "strict") return std::string("Strict");
  if (lowered == "lax") return std::string("Lax");
  if (lowered == "none") return std::string("None");
  if (lowered == "unspecified") return std::string("Unspecified");
  return std::nullopt;
}

}  // namespace

std::optional<UrlParts> ParseUrl(const std::string& url) {
  const auto scheme_end = url.find("://");
  if (scheme_end == std::string::npos || scheme_end == 0) return std::nullopt;
  UrlParts parts;
  parts.scheme = Lower(url.substr(0, scheme_end));
  const std::size_t authority_start = scheme_end + 3;
  const std::size_t authority_end = url.find_first_of("/?#", authority_start);
  std::string authority = url.substr(authority_start, authority_end == std::string::npos
                                                          ? std::string::npos
                                                          : authority_end - authority_start);
  if (const auto at = authority.rfind('@'); at != std::string::npos) authority = authority.substr(at + 1);
  if (!authority.empty() && authority.front() == '[') {
    const auto close = authority.find(']');
    if (close == std::string::npos) return std::nullopt;
    parts.host = Lower(authority.substr(0, close + 1));
  } else {
    parts.host = Lower(authority.substr(0, authority.find(':')));
  }
  if (parts.host.empty()) return std::nullopt;
  if (authority_end == std::string::npos || url[authority_end] != '/') {
    parts.path = "/";
  } else {
    const auto path_end = url.find_first_of("?#", authority_end);
    parts.path = url.substr(authority_end, path_end == std::string::npos ? std::string::npos
                                                                          : path_end - authority_end);
  }
  return parts;
}

namespace {

bool DomainMatches(const Cookie& cookie, const std::string& host) {
  const std::string cookie_host = cookie.host();
  if (host == cookie_host) return true;
  if (cookie.host_only()) return false;
  return host.size() > cookie_host.size() &&
         host.compare(host.size() - cookie_host.size(), cookie_host.size(), cookie_host) == 0 &&
         host[host.size() - cookie_host.size() - 1] == '.';
}

bool PathMatches(const std::string& cookie_path, const std::string& request_path) {
  if (request_path == cookie_path) return true;
  if (request_path.rfind(cookie_path, 0) != 0) return false;
  return cookie_path.back() == '/' || request_path[cookie_path.size()] == '/';
}

}  // namespace

ParsedCookie ParseCookie(const nlohmann::json& json) {
  ParsedCookie parsed;
  if (!json.is_object()) {
    parsed.problem = CookieProblem::kMalformed;
    return parsed;
  }
  const auto string_field = [&](const char* name) -> const nlohmann::json* {
    const auto it = json.find(name);
    return it != json.end() && it->is_string() ? &*it : nullptr;
  };
  const auto* domain = string_field("domain");
  const auto* name = string_field("name");
  const auto* value = string_field("value");
  if (domain == nullptr || name == nullptr || value == nullptr) {
    parsed.problem = CookieProblem::kMalformed;
    return parsed;
  }

  Cookie cookie;
  cookie.domain = Lower(domain->get<std::string>());
  cookie.name = name->get<std::string>();
  cookie.value = value->get<std::string>();
  if (const auto* path = string_field("path"); path != nullptr && !path->get<std::string>().empty()) {
    cookie.path = path->get<std::string>();
  }
  if (const auto it = json.find("expires"); it != json.end() && !it->is_null()) {
    if (!it->is_number_integer()) {
      parsed.problem = CookieProblem::kMalformed;
      return parsed;
    }
    cookie.expires = it->get<std::int64_t>();
  }
  for (const auto& [field, target] : {std::pair<const char*, bool*>{"secure", &cookie.secure},
                                      std::pair<const char*, bool*>{"httpOnly", &cookie.http_only}}) {
    const auto it = json.find(field);
    if (it == json.end() || it->is_null()) continue;
    if (!it->is_boolean()) {
      parsed.problem = CookieProblem::kMalformed;
      return parsed;
    }
    *target = it->get<bool>();
  }
  const auto same_site = json.find("sameSite");
  const auto canonical_same_site =
      same_site == json.end() ? std::nullopt : CanonicalSameSite(*same_site);
  if (!canonical_same_site) {
    parsed.problem = CookieProblem::kMalformed;
    return parsed;
  }
  cookie.same_site = *canonical_same_site;
  if (const auto it = json.find("partitioned"); it != json.end() && !it->is_null()) {
    if (!it->is_boolean()) {
      parsed.problem = CookieProblem::kMalformed;
      return parsed;
    }
    if (it->get<bool>()) {
      parsed.problem = CookieProblem::kPartitioned;
      return parsed;
    }
  }

  if (cookie.name.empty() || cookie.domain.empty() || cookie.domain == "." ||
      cookie.path.front() != '/' || cookie.domain.find_first_of(" \t;,") != std::string::npos) {
    parsed.problem = CookieProblem::kMalformed;
    return parsed;
  }
  if (cookie.name.size() + cookie.value.size() > kMaxCookieBytes) {
    parsed.problem = CookieProblem::kTooLarge;
    return parsed;
  }
  if (IsLoopbackHost(cookie.host())) {
    parsed.problem = CookieProblem::kLoopbackHost;
    return parsed;
  }
  parsed.cookie = std::move(cookie);
  return parsed;
}

nlohmann::json CookieToJson(const Cookie& cookie) {
  nlohmann::json json = {
      {"domain", cookie.domain}, {"path", cookie.path},  {"name", cookie.name},
      {"value", cookie.value},   {"secure", cookie.secure}, {"httpOnly", cookie.http_only},
  };
  json["expires"] = cookie.expires ? nlohmann::json(*cookie.expires) : nlohmann::json(nullptr);
  json["sameSite"] = cookie.same_site;
  return json;
}

std::string CookieKey(const std::string& domain, const std::string& path, const std::string& name) {
  return nlohmann::json::array({domain, path, name}).dump();
}

std::string CookieKey(const Cookie& cookie) {
  return CookieKey(cookie.domain, cookie.path, cookie.name);
}

std::string CookieFingerprint(const Cookie& cookie) {
  Sha256 hasher;
  // Length-prefixed so no field content can shift into another field.
  const auto field = [&](const std::string& text) {
    const std::string length = std::to_string(text.size()) + ":";
    hasher.Update(length);
    hasher.Update(text);
  };
  field(cookie.domain);
  field(cookie.path);
  field(cookie.name);
  field(cookie.value);
  field(cookie.expires ? std::to_string(*cookie.expires) : std::string("-"));
  field(cookie.secure ? "1" : "0");
  field(cookie.http_only ? "1" : "0");
  field(cookie.same_site);
  return Hex(hasher.Finish());
}

bool CookieMatchesUrl(const Cookie& cookie, const UrlParts& url) {
  if (cookie.secure && url.scheme != "https" && url.scheme != "wss") return false;
  return DomainMatches(cookie, url.host) && PathMatches(cookie.path, url.path);
}

bool CookieMatchesUrl(const Cookie& cookie, const std::string& url) {
  const auto parts = ParseUrl(url);
  return parts && CookieMatchesUrl(cookie, *parts);
}

std::string CookieProblemName(CookieProblem problem) {
  switch (problem) {
    case CookieProblem::kNone: return "none";
    case CookieProblem::kMalformed: return "malformed";
    case CookieProblem::kTooLarge: return "too_large";
    case CookieProblem::kLoopbackHost: return "loopback_host";
    case CookieProblem::kPartitioned: return "partitioned";
  }
  return "unknown";
}

}  // namespace kelpie::sync
