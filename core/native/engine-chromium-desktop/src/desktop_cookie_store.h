#pragma once

// Store-level cookie operations shared by cookie sync and the store-level
// automation methods (get-cookies all/partition, set-cookies, copy-cookies).
// They work on a whole cookie manager, never on one page. The engine-neutral
// logic lives here so it is tested without CEF; desktop_cookie_store_cef.cpp
// supplies the CefCookieManager backend.
//
// Wire shape (core-sync): {domain, path, name, value, expires: Unix seconds |
// null, secure, httpOnly, sameSite: Strict|Lax|None|Unspecified}. A leading
// dot marks a domain cookie; no dot is host-only.

#include <functional>
#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie::desktop_cookie_store {

using Json = nlohmann::json;
using Cancelled = std::function<bool()>;

inline constexpr std::size_t kMaxCookiesPerWrite = 500;

class CookieBackend {
 public:
  struct Write {
    Json cookie;          // wire shape
    bool remove = false;  // delete exactly the cookie's (domain, path, name)
  };

  virtual ~CookieBackend() = default;
  // Every cookie in the store, wire shape. A backend that can tell marks
  // partitioned (CHIPS) cookies with "partitioned": true. False on failure,
  // never an invented empty list.
  virtual bool VisitAll(Json* cookies, const Cancelled& cancelled) = 0;
  // Applies the writes in order: one success flag each, or nullopt when they
  // could not be carried out at all.
  virtual std::optional<std::vector<bool>> Apply(const std::vector<Write>& writes, const Cancelled& cancelled) = 0;
};

// Lower-case, without the leading dot.
std::string BareDomain(std::string domain);

// The read-back contract: every cookie with the op cookie's name whose domain,
// with or without a leading dot, equals the op's domain without its dot.
Json Readback(const Json& cookies, const Json& op_cookie);

// Cookie sync snapshot: the whole store minus partitioned cookies, coverage
// {"all":true}.
bool SyncSnapshot(CookieBackend& backend, Json* cookies, Json* coverage, const Cancelled& cancelled);

// core-sync planned ops → [{id, ok, readback}]. Ops run in rounds holding at
// most one op per (bare domain, name), so each op's read-back is taken right
// after it and before any later op could touch the same cookies. nullopt
// when a write could not be scheduled or a read-back failed.
std::optional<Json> ApplySyncOps(CookieBackend& backend, const Json& ops, const Cancelled& cancelled);

// Automation shape (docs/api/cookies.md, CookieInfo): {name, value, domain,
// path, expires: ISO-8601 UTC or null for a session cookie, httpOnly, secure,
// sameSite}.
Json ToAutomation(const Json& wire);

struct ParsedCookie {
  std::optional<Json> wire;
  std::string error;
};
// One set-cookies entry in the shape get-cookies returns → wire shape. Every
// field is required: name (non-empty), value, domain (leading dot = domain
// cookie, none = host-only), path (starting "/"), expires (ISO-8601 UTC,
// whole Unix seconds or null), httpOnly, secure and sameSite
// (Strict|Lax|None|Unspecified).
ParsedCookie FromAutomation(const Json& input);

// RFC 6265 matching for get-cookies' `url`: domain match, path match and
// Secure only over https. nullopt when `url` is not an absolute http(s) URL.
std::optional<bool> MatchesUrl(const Json& automation_cookie, const std::string& url);

// The cookie's host equals `filter` or is a subdomain of it (leading dots and
// case ignored on both sides).
bool DomainMatches(const std::string& cookie_domain, const std::string& filter);

// Applies get-cookies' optional `domain`, `name` and `url` filters, which
// combine. `url` must already have been validated with MatchesUrl.
Json Filter(const Json& automation_cookies, const std::optional<std::string>& domain,
            const std::optional<std::string>& name, const std::optional<std::string>& url = std::nullopt);

// Parses every set-cookies entry before anything is written: a malformed
// entry fails the whole request with "cookies[<index>]: <reason>".
std::optional<std::vector<Json>> ParseCookies(const Json& inputs, std::string* error);

// set-cookies on already-parsed wire cookies: {set, failed: [{index, name,
// domain, error}]} where failed lists only cookies the engine refused.
Json WriteCookies(CookieBackend& backend, const std::vector<Json>& cookies, const Cancelled& cancelled);

// copy-cookies: every non-partitioned cookie of `from` (optionally only
// `domain` and its subdomains) written into `to`, replacing cookies with the
// same key; values never leave the device. {copied, failed: [{name, domain,
// error}]}, or nullopt when the source could not be read.
std::optional<Json> CopyCookies(CookieBackend& from, CookieBackend& to, const std::optional<std::string>& domain,
                                const Cancelled& cancelled);

}  // namespace kelpie::desktop_cookie_store
