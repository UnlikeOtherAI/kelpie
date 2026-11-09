#include <cassert>
#include <string>

#include "cookie.h"

using namespace kelpie::sync;
using nlohmann::json;

namespace {

json Base() {
  return {{"domain", ".Example.COM"}, {"path", "/"}, {"name", "sid"}, {"value", "v"},
          {"expires", 1733742000},    {"secure", true}, {"httpOnly", true}, {"sameSite", "lax"}};
}

void TestCanonicalisation() {
  const auto parsed = ParseCookie(Base());
  assert(parsed.cookie);
  assert(parsed.cookie->domain == ".example.com");
  assert(parsed.cookie->same_site == "Lax");
  assert(!parsed.cookie->host_only());
  assert(parsed.cookie->host() == "example.com");

  json missing_path = Base();
  missing_path.erase("path");
  assert(ParseCookie(missing_path).cookie->path == "/");

  json session = Base();
  session["expires"] = nullptr;
  assert(!ParseCookie(session).cookie->expires);
}

void TestRejections() {
  json fractional = Base();
  fractional["expires"] = 1.5;
  assert(ParseCookie(fractional).problem == CookieProblem::kMalformed);

  json unknown_same_site = Base();
  unknown_same_site["sameSite"] = nullptr;  // an engine that cannot tell must not guess
  assert(ParseCookie(unknown_same_site).problem == CookieProblem::kMalformed);
  unknown_same_site.erase("sameSite");
  assert(ParseCookie(unknown_same_site).problem == CookieProblem::kMalformed);

  json unspecified = Base();
  unspecified["sameSite"] = "Unspecified";
  assert(ParseCookie(unspecified).cookie->same_site == "Unspecified");

  json large = Base();
  large["value"] = std::string(kMaxCookieBytes, 'x');
  assert(ParseCookie(large).problem == CookieProblem::kTooLarge);

  for (const char* host : {"localhost", "app.localhost", "127.0.0.1", "::1", "[::1]"}) {
    json loopback = Base();
    loopback["domain"] = host;
    assert(ParseCookie(loopback).problem == CookieProblem::kLoopbackHost);
  }
  json not_loopback = Base();
  not_loopback["domain"] = "127.example.com";
  assert(ParseCookie(not_loopback).cookie);

  json partitioned = Base();
  partitioned["partitioned"] = true;
  assert(ParseCookie(partitioned).problem == CookieProblem::kPartitioned);

  json bad_path = Base();
  bad_path["path"] = "relative";
  assert(ParseCookie(bad_path).problem == CookieProblem::kMalformed);
}

void TestKeysCannotCollide() {
  // The delimiter-joined key would make these two the same cookie.
  assert(CookieKey("example.com", "/a|b", "sid") != CookieKey("example.com", "/a", "b|sid"));
  assert(CookieKey(".example.com", "/", "sid") != CookieKey("example.com", "/", "sid"));
}

void TestFingerprint() {
  const Cookie a = *ParseCookie(Base()).cookie;
  Cookie b = a;
  assert(CookieFingerprint(a) == CookieFingerprint(b));
  b.same_site = "Unspecified";
  assert(CookieFingerprint(a) != CookieFingerprint(b));
  Cookie c = a;
  c.name = "si";
  c.value = "dv";  // same concatenation, different fields
  assert(CookieFingerprint(a) != CookieFingerprint(c));
}

void TestUrlMatching() {
  Cookie domain_cookie = *ParseCookie(Base()).cookie;  // .example.com, Secure, path /
  assert(CookieMatchesUrl(domain_cookie, "https://example.com/"));
  assert(CookieMatchesUrl(domain_cookie, "https://www.example.com/a/b?x#y"));
  assert(!CookieMatchesUrl(domain_cookie, "http://example.com/"));  // Secure
  assert(!CookieMatchesUrl(domain_cookie, "https://badexample.com/"));

  Cookie host_only = domain_cookie;
  host_only.domain = "example.com";
  assert(CookieMatchesUrl(host_only, "https://example.com:8443/"));
  assert(!CookieMatchesUrl(host_only, "https://www.example.com/"));

  Cookie scoped = domain_cookie;
  scoped.path = "/account";
  assert(!CookieMatchesUrl(scoped, "https://example.com/"));
  assert(CookieMatchesUrl(scoped, "https://example.com/account"));
  assert(CookieMatchesUrl(scoped, "https://example.com/account/settings"));
  assert(!CookieMatchesUrl(scoped, "https://example.com/accounts"));

  assert(!CookieMatchesUrl(domain_cookie, "not a url"));
}

}  // namespace

int main() {
  TestCanonicalisation();
  TestRejections();
  TestKeysCannotCollide();
  TestFingerprint();
  TestUrlMatching();
  return 0;
}
