#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "kelpie/internal_scheme.h"

// The Kelpie start page: first-party content served from `kelpie://start`.
//
// Nothing in this header touches CEF, so both the Chromium and the stub
// configuration compile it and both run its tests. The CEF-only part — scheme
// registration and the resource handler — lives in `src/start_page_scheme.h`.
namespace kelpie::start_page {

// A resource the start page scheme serves. `path` is the part after
// `kelpie://start/`; the empty path is the document itself.
struct Resource {
  std::string_view path;
  std::string_view mime_type;
  std::string_view body;
};

// A media type split into the two fields CEF wants separately. CefResponse
// takes a bare type in SetMimeType and the encoding in SetCharset; handing it
// a full `text/html; charset=utf-8` header value leaves Chromium unable to
// match the type and it falls back to rendering the document as plain text.
struct MediaType {
  std::string_view type;
  std::string_view charset;
};

MediaType SplitMediaType(std::string_view value);

// The embedded assets. Defined by the generated translation unit that
// `cmake/EmbedResource.cmake` produces from `resources/start_page/`.
namespace resources {
extern const std::string_view kIndexHtml;
extern const std::string_view kStartCss;
extern const std::string_view kStartJs;
extern const std::string_view kAppIconPng;
}  // namespace resources

// Every static asset, in the order the document requests them.
std::vector<Resource> StaticResources();

// Resolves a `kelpie://start/...` URL to a static asset. Returns nullptr for the
// dynamic `data.json` payload and for anything unknown, so the caller can tell
// "serve bytes" from "build JSON" from "404".
const Resource* FindStaticResource(std::string_view url);

// True when the URL addresses the dynamic bookmark/history payload.
bool IsDataRequest(std::string_view url);

// Resolves a `kelpie://start/preview/<key>.jpg` URL to the host whose
// screenshot it names, or nullopt for anything else. The key is the host's hex
// encoding (`SitePreviewStore::KeyForHost`), so a request path can never name a
// file outside the preview store.
std::optional<std::string> PreviewHostForUrl(std::string_view url);

// The relative URL the page uses for a host's screenshot. `version` changes on
// every new capture, so the page never shows a stale image.
std::string PreviewPath(const std::string& host, std::uint64_t version);

// What the start page can show for one site, beyond its URL and title.
struct SiteImages {
  // Base64 PNG, or empty when no favicon is known.
  std::string favicon_png_base64;
  // Set when a screenshot is stored; see PreviewPath.
  std::optional<std::uint64_t> preview_version;
};

// Resolves a host's images. The production implementation reads the session's
// FaviconRegistry first and the persistent SitePreviewStore second.
using SiteLookup = std::function<SiteImages(const std::string& host)>;

// The number of sites the "Recent" grid shows, mirroring `StartPageView`.
inline constexpr std::size_t kRecentSiteLimit = 8;

// Builds the `data.json` body from the shared stores' own JSON.
//
// `bookmarks_json` is `BookmarkStore::ToJson()` and `history_json` is
// `HistoryStore::ToJson()`; both are taken as strings so this stays free of a
// dependency on the store objects and is trivially testable.
//
// `bookmarks` lists every favourite page. `recent` lists the most recently
// visited sites, newest first: one entry per host (its latest visit), skipping
// hosts that are already favourites, capped at `recent_limit`.
//
// Entries carry only `url`, `title`, and — when `site_lookup` resolves them — a
// `favicon` `data:` URI and a `thumbnail` preview path. Nothing else from the
// stores reaches the page, so a store field added later cannot leak into
// rendered content by accident.
std::string BuildDataJson(const std::string& bookmarks_json,
                          const std::string& history_json,
                          std::size_t recent_limit = kRecentSiteLimit,
                          const SiteLookup& site_lookup = nullptr);

}  // namespace kelpie::start_page
