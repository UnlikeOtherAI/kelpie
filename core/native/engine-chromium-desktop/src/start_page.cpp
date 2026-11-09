#include "kelpie/start_page.h"

#include <algorithm>
#include <cctype>
#include <unordered_set>

#include <nlohmann/json.hpp>

#include "kelpie/favicon_registry.h"
#include "kelpie/site_preview_store.h"

namespace kelpie::start_page {
namespace {

using nlohmann::json;

constexpr std::string_view kDataPath = "data.json";
constexpr std::string_view kPreviewPrefix = "preview/";
constexpr std::string_view kPreviewSuffix = ".jpg";

// Strips `kelpie://start` and any leading slash, so both `kelpie://start` and
// `kelpie://start/` resolve to the document and `kelpie://start/start.css`
// resolves to `start.css`. The query and fragment are not part of the path.
std::string_view PathForUrl(std::string_view url) {
  if (!IsStartPageUrl(url)) {
    return std::string_view();
  }
  std::string_view rest = url.substr(kInternalSchemePrefix.size());
  const std::size_t boundary = rest.find_first_of("/?#");
  if (boundary == std::string_view::npos) {
    return std::string_view();
  }
  if (rest[boundary] != '/') {
    return std::string_view();
  }
  std::string_view path = rest.substr(boundary + 1);
  const std::size_t cut = path.find_first_of("?#");
  if (cut != std::string_view::npos) {
    path = path.substr(0, cut);
  }
  return path;
}

// The start page renders every entry as a link in its own origin, so only real
// web URLs may reach it. A `javascript:` bookmark would otherwise become a
// same-origin script injection the moment the user clicked the tile.
bool IsWebUrl(std::string_view url) {
  for (const std::string_view scheme : {std::string_view("http://"), std::string_view("https://")}) {
    if (url.size() <= scheme.size()) {
      continue;
    }
    bool matches = true;
    for (std::size_t index = 0; index < scheme.size(); ++index) {
      if (static_cast<char>(std::tolower(static_cast<unsigned char>(url[index]))) != scheme[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}

std::string FaviconDataUri(const std::string& png_base64) {
  return png_base64.empty() ? std::string() : "data:image/png;base64," + png_base64;
}

}  // namespace

MediaType SplitMediaType(std::string_view value) {
  const std::size_t separator = value.find(';');
  if (separator == std::string_view::npos) return {value, {}};
  MediaType media{value.substr(0, separator), {}};
  const std::size_t charset = value.find("charset=", separator);
  if (charset != std::string_view::npos) {
    media.charset = value.substr(charset + 8);
  }
  return media;
}

std::vector<Resource> StaticResources() {
  return {
      // The empty path is the document, so `kelpie://start` loads the page.
      {std::string_view(), "text/html; charset=utf-8", resources::kIndexHtml},
      {"index.html", "text/html; charset=utf-8", resources::kIndexHtml},
      {"start.css", "text/css; charset=utf-8", resources::kStartCss},
      {"start.js", "text/javascript; charset=utf-8", resources::kStartJs},
      {"app-icon.png", "image/png", resources::kAppIconPng},
  };
}

const Resource* FindStaticResource(std::string_view url) {
  if (!IsStartPageUrl(url)) {
    return nullptr;
  }
  const std::string_view path = PathForUrl(url);
  static const std::vector<Resource> table = StaticResources();
  const auto it = std::find_if(table.begin(), table.end(), [path](const Resource& resource) {
    return resource.path == path;
  });
  return it == table.end() ? nullptr : &*it;
}

bool IsDataRequest(std::string_view url) {
  return IsStartPageUrl(url) && PathForUrl(url) == kDataPath;
}

std::optional<std::string> PreviewHostForUrl(std::string_view url) {
  const std::string_view path = PathForUrl(url);
  if (path.size() <= kPreviewPrefix.size() + kPreviewSuffix.size() ||
      path.substr(0, kPreviewPrefix.size()) != kPreviewPrefix ||
      path.substr(path.size() - kPreviewSuffix.size()) != kPreviewSuffix) {
    return std::nullopt;
  }
  const std::string_view key =
      path.substr(kPreviewPrefix.size(), path.size() - kPreviewPrefix.size() - kPreviewSuffix.size());
  return SitePreviewStore::HostForKey(key);
}

std::string PreviewPath(const std::string& host, std::uint64_t version) {
  return std::string(kPreviewPrefix) + SitePreviewStore::KeyForHost(host) + std::string(kPreviewSuffix) +
         "?v=" + std::to_string(version);
}

std::string BuildDataJson(const std::string& bookmarks_json,
                          const std::string& history_json,
                          std::size_t recent_limit,
                          const SiteLookup& site_lookup) {
  const json bookmarks = json::parse(bookmarks_json, nullptr, false);
  const json history = json::parse(history_json, nullptr, false);

  json payload{{"bookmarks", json::array()}, {"recent", json::array()}};
  // Hosts already on the page; Recent shows each site once, and never one that
  // is already a favourite.
  std::unordered_set<std::string> shown_hosts;

  // Returns the entry for a usable store record, or null to skip it.
  const auto entry_for = [&site_lookup](const json& source) -> json {
    // `value()` throws on a type mismatch, and store JSON can be anything after
    // a hand-edited or corrupted profile file, so the types are checked first.
    if (!source.is_object()) return nullptr;
    const auto url_field = source.find("url");
    if (url_field == source.end() || !url_field->is_string()) return nullptr;
    const auto url = url_field->get<std::string>();
    if (!IsWebUrl(url)) return nullptr;
    const auto title_field = source.find("title");
    const std::string title =
        title_field != source.end() && title_field->is_string() ? title_field->get<std::string>()
                                                                : std::string();
    json entry{{"url", url}, {"title", title}};
    const std::string host = FaviconRegistry::HostForUrl(url);
    if (site_lookup && !host.empty()) {
      const SiteImages images = site_lookup(host);
      if (!images.favicon_png_base64.empty()) entry["favicon"] = FaviconDataUri(images.favicon_png_base64);
      if (images.preview_version) entry["thumbnail"] = PreviewPath(host, *images.preview_version);
    }
    return entry;
  };

  if (bookmarks.is_array()) {
    for (const json& bookmark : bookmarks) {
      json entry = entry_for(bookmark);
      if (entry.is_null()) continue;
      shown_hosts.insert(FaviconRegistry::HostForUrl(entry["url"].get<std::string>()));
      payload["bookmarks"].push_back(std::move(entry));
    }
  }

  // `HistoryStore::ToJson` is newest-first, so the first entry per host is that
  // site's latest visit.
  if (history.is_array()) {
    for (const json& visit : history) {
      if (payload["recent"].size() >= recent_limit) break;
      if (!visit.is_object() || !visit.contains("url") || !visit["url"].is_string()) continue;
      const std::string host = FaviconRegistry::HostForUrl(visit["url"].get<std::string>());
      if (host.empty() || shown_hosts.count(host) != 0) continue;
      json entry = entry_for(visit);
      if (entry.is_null()) continue;
      shown_hosts.insert(host);
      payload["recent"].push_back(std::move(entry));
    }
  }

  return payload.dump();
}

}  // namespace kelpie::start_page
