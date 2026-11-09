#pragma once

#include <cstdint>
#include <optional>
#include <string>

#include <nlohmann/json.hpp>

namespace kelpie::sync {

// One cookie in the sync wire shape. Engines convert to and from this shape;
// core-sync never talks to an engine directly.
struct Cookie {
  std::string domain;  // lower-case; a leading '.' marks a domain cookie
  std::string path = "/";
  std::string name;
  std::string value;
  std::optional<std::int64_t> expires;  // whole Unix seconds; nullopt = session cookie
  bool secure = false;
  bool http_only = false;
  std::string same_site = "Unspecified";  // "Strict", "Lax", "None" or "Unspecified" (absent)

  bool host_only() const { return domain.empty() || domain.front() != '.'; }
  // Host without the leading dot, used for scope matching.
  std::string host() const { return host_only() ? domain : domain.substr(1); }
};

enum class CookieProblem {
  kNone,
  kMalformed,     // missing or wrongly typed fields
  kTooLarge,      // name + value over the per-cookie limit
  kLoopbackHost,  // names a different server on every device
  kPartitioned,   // CHIPS cookie; its partition key does not travel
};

struct ParsedCookie {
  std::optional<Cookie> cookie;
  CookieProblem problem = CookieProblem::kNone;
};

inline constexpr std::size_t kMaxCookieBytes = 4096;

// Parses and canonicalises the wire shape. Domains are lower-cased, paths
// default to "/", expiry must be an integer and sameSite must be one of the
// four values (case-insensitive); an engine that cannot tell must not guess.
ParsedCookie ParseCookie(const nlohmann::json& json);
nlohmann::json CookieToJson(const Cookie& cookie);

// The JSON array ["domain","path","name"], so no delimiter can make two
// cookies collide. This is the identity two engines must agree on.
std::string CookieKey(const Cookie& cookie);
std::string CookieKey(const std::string& domain, const std::string& path, const std::string& name);

// SHA-256 over every canonical field, hex. Compared only on the device that
// produced it, so engine-specific normalisation cannot cause churn.
std::string CookieFingerprint(const Cookie& cookie);

struct UrlParts {
  std::string scheme;  // lower-case
  std::string host;    // lower-case, IPv6 in brackets, no port
  std::string path;    // starts with '/'
};
std::optional<UrlParts> ParseUrl(const std::string& url);

// True when the cookie would be returned for the URL under RFC 6265 rules
// (domain match, path match, Secure requires https). Used to decide which
// metadata entries a partial (URL-based) scan actually observed.
bool CookieMatchesUrl(const Cookie& cookie, const UrlParts& url);
bool CookieMatchesUrl(const Cookie& cookie, const std::string& url);

std::string CookieProblemName(CookieProblem problem);

}  // namespace kelpie::sync
