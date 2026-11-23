#pragma once

#include <algorithm>
#include <cctype>
#include <string>

namespace kelpie {

// Rules for the windows and app links a page asks for. Header-only and free of
// CEF so the shells' tests can check them directly.

inline std::string LowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

// The URL scheme, lowercased, or empty when the URL has none.
inline std::string UrlScheme(const std::string& url) {
  const auto colon = url.find(':');
  if (colon == std::string::npos || colon == 0) return {};
  for (std::size_t i = 0; i < colon; ++i) {
    const unsigned char c = static_cast<unsigned char>(url[i]);
    const bool valid = std::isalpha(c) || (i > 0 && (std::isdigit(c) || c == '+' || c == '-' || c == '.'));
    if (!valid) return {};
  }
  return LowerAscii(url.substr(0, colon));
}

// A link Chromium cannot load itself, such as `slack:` or `mailto:`.
inline bool IsAppLink(const std::string& url) {
  static const char* const kWebSchemes[] = {
      "http", "https", "about", "data", "blob", "file", "javascript", "chrome", "chrome-error",
      "chrome-extension", "devtools", "view-source", "filesystem", "ws", "wss", "kelpie"};
  const std::string scheme = UrlScheme(url);
  if (scheme.empty()) return false;
  return std::none_of(std::begin(kWebSchemes), std::end(kWebSchemes),
                      [&scheme](const char* web) { return scheme == web; });
}

// App schemes Chrome never hands to the OS, which can run local programs or
// read local files on Windows.
inline bool IsDeniedAppLink(const std::string& url) {
  static const char* const kDenied[] = {"afp", "disk", "disks", "hcp", "ie.http", "mk", "ms-help", "ms-msdt",
                                        "nntp", "res", "shell", "vbscript", "vnd.ms.radio"};
  const std::string scheme = UrlScheme(url);
  return std::any_of(std::begin(kDenied), std::end(kDenied), [&scheme](const char* denied) { return scheme == denied; });
}

// `scheme://host[:port]` for an http(s) URL, otherwise empty.
inline std::string OriginOf(const std::string& url) {
  const std::string scheme = UrlScheme(url);
  if (scheme != "http" && scheme != "https") return {};
  const std::string prefix = scheme + "://";
  if (LowerAscii(url.substr(0, prefix.size())) != prefix) return {};
  std::string authority = url.substr(prefix.size(), url.find_first_of("/?#", prefix.size()) - prefix.size());
  if (const auto at = authority.rfind('@'); at != std::string::npos) authority.erase(0, at + 1);
  if (authority.empty()) return {};
  return prefix + LowerAscii(authority);
}

// Chromium cannot hand a new-window context to a Kelpie tab, so a tab is
// replayed from the URL. A pop-up keeps its native window, and so does a blank
// window the opener writes into or navigates later.
inline bool OpensAsTab(bool popup_disposition, const std::string& url) {
  return !popup_disposition && !OriginOf(url).empty();
}

}  // namespace kelpie
