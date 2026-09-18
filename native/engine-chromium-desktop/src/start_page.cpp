#include "kelpie/start_page.h"

#include <algorithm>

#include <nlohmann/json.hpp>

#include "kelpie/favicon_registry.h"

namespace kelpie::start_page {
namespace {

using nlohmann::json;

constexpr std::string_view kDataPath = "data.json";

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

std::string FaviconDataUri(const std::string& png_base64) {
  return png_base64.empty() ? std::string() : "data:image/png;base64," + png_base64;
}

}  // namespace

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

std::string BuildDataJson(const std::string& bookmarks_json,
                          const std::string& history_json,
                          std::size_t recent_limit) {
  return BuildDataJson(bookmarks_json, history_json, recent_limit, nullptr);
}

std::string BuildDataJson(const std::string& bookmarks_json,
                          const std::string& history_json,
                          std::size_t recent_limit,
                          const FaviconLookup& favicon_lookup) {
  const json bookmarks = json::parse(bookmarks_json, nullptr, false);
  const json history = json::parse(history_json, nullptr, false);

  json payload{{"bookmarks", json::array()}, {"recent", json::array()}};

  const auto append = [&favicon_lookup](json& target, const json& source) {
    const std::string url = source.value("url", std::string());
    if (url.empty()) {
      return;
    }
    json entry{{"url", url}, {"title", source.value("title", std::string())}};
    if (favicon_lookup) {
      const std::string host = FaviconRegistry::HostForUrl(url);
      const std::string favicon = host.empty() ? std::string() : favicon_lookup(host);
      if (!favicon.empty()) {
        entry["favicon"] = FaviconDataUri(favicon);
      }
    }
    target.push_back(std::move(entry));
  };

  if (bookmarks.is_array()) {
    for (const json& bookmark : bookmarks) {
      if (bookmark.is_object()) {
        append(payload["bookmarks"], bookmark);
      }
    }
  }

  // `HistoryStore::ToJson` is already newest-first, matching
  // `historyStore.entries.prefix(20)` on macOS.
  if (history.is_array()) {
    for (const json& entry : history) {
      if (payload["recent"].size() >= recent_limit) {
        break;
      }
      if (entry.is_object()) {
        append(payload["recent"], entry);
      }
    }
  }

  return payload.dump();
}

}  // namespace kelpie::start_page
