#pragma once

#include <functional>
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

// Resolves a host to a base64-encoded PNG favicon, or an empty string when none
// is known. `FaviconRegistry::Lookup` is the production implementation.
using FaviconLookup = std::function<std::string(const std::string& host)>;

// Builds the `data.json` body from the shared stores' own JSON.
//
// `bookmarks_json` is `BookmarkStore::ToJson()` and `history_json` is
// `HistoryStore::ToJson()`; both are taken as strings so this stays free of a
// dependency on the store objects and is trivially testable. History is newest
// first and capped at `recent_limit`, mirroring
// `Array(historyStore.entries.prefix(20))` on macOS.
//
// Entries carry only `url`, `title`, and — when `favicon_lookup` resolves one —
// a `favicon` `data:` URI. Nothing else from the stores reaches the page, so a
// store field added later cannot leak into rendered content by accident.
std::string BuildDataJson(const std::string& bookmarks_json,
                          const std::string& history_json,
                          std::size_t recent_limit = 20);

std::string BuildDataJson(const std::string& bookmarks_json,
                          const std::string& history_json,
                          std::size_t recent_limit,
                          const FaviconLookup& favicon_lookup);

}  // namespace kelpie::start_page
