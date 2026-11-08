#pragma once

#include <cctype>
#include <string>
#include <string_view>

namespace kelpie {

// Kelpie's own first-party pages are served from a custom scheme so that the
// start page is real web content rendered by the same engine rather than a
// script injected into a third-party document.
inline constexpr std::string_view kInternalScheme = "kelpie";
inline constexpr std::string_view kInternalSchemePrefix = "kelpie://";
inline constexpr std::string_view kStartPageUrl = "kelpie://start";
// The start page fetches its bookmark and history payload from this URL on the
// same scheme, so no cross-origin request and no injected bridge is required.
inline constexpr std::string_view kStartPageDataUrl = "kelpie://start/data.json";

// Case-insensitive `kelpie://` prefix test. Schemes are case-insensitive per
// RFC 3986, and Chromium normalises them to lower case before a navigation is
// reported, but callers also pass raw user input.
inline bool IsInternalSchemeUrl(std::string_view url) {
  if (url.size() < kInternalSchemePrefix.size()) {
    return false;
  }
  for (std::size_t index = 0; index < kInternalSchemePrefix.size(); ++index) {
    const auto lowered = static_cast<char>(
        std::tolower(static_cast<unsigned char>(url[index])));
    if (lowered != kInternalSchemePrefix[index]) {
      return false;
    }
  }
  return true;
}

// True for `kelpie://start` and any path or query below it, so the data URL and
// a trailing slash are recognised as the same first-party page.
inline bool IsStartPageUrl(std::string_view url) {
  if (!IsInternalSchemeUrl(url)) {
    return false;
  }
  std::string_view rest = url.substr(kInternalSchemePrefix.size());
  const std::size_t boundary = rest.find_first_of("/?#");
  const std::string_view host = boundary == std::string_view::npos ? rest : rest.substr(0, boundary);
  if (host.size() != 5) {
    return false;
  }
  for (std::size_t index = 0; index < host.size(); ++index) {
    const auto lowered = static_cast<char>(std::tolower(static_cast<unsigned char>(host[index])));
    if (lowered != "start"[index]) {
      return false;
    }
  }
  return true;
}

}  // namespace kelpie
