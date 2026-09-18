#pragma once

#include <cstddef>
#include <list>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace kelpie {

// Host-keyed store of the favicons Chromium has downloaded this session.
//
// Favicons belong to a site, not to a tab: the tab strip, the start page's
// Favourites grid, and its Recent list all want "the icon for this host". The
// registry is a bounded LRU so a long session cannot grow it without limit, and
// it holds no CEF types so both build configurations compile and test it.
//
// Values are base64-encoded PNG. Base64 is what the HTTP layer, the start page's
// `data:` URIs, and `TabSnapshot` all need, so decoding once at the boundary and
// storing the encoded form avoids re-encoding on every read.
class FaviconRegistry {
 public:
  static constexpr std::size_t kDefaultCapacity = 64;

  explicit FaviconRegistry(std::size_t capacity = kDefaultCapacity);

  // Inserts or refreshes `host`, promoting it to most-recently-used. An empty
  // host or empty payload is ignored so a failed download cannot evict a good
  // entry. Returns false when the call was ignored.
  bool Store(const std::string& host, std::string png_base64);

  // Returns the entry for `host` and promotes it. `std::nullopt` when absent.
  std::optional<std::string> Lookup(const std::string& host);

  // Read-only probe that does not change recency — used by tests and by
  // snapshot paths that must not reorder the cache.
  std::optional<std::string> Peek(const std::string& host) const;

  void Clear();
  std::size_t size() const;
  std::size_t capacity() const { return capacity_; }

  // Most-recently-used first. Exposed for tests to assert eviction order.
  std::vector<std::string> HostsMostRecentFirst() const;

  // Lower-cases `host` the way the registry keys it. Exposed so callers can
  // agree on the key without duplicating the rule.
  static std::string NormalizeHost(std::string_view host);

  // Extracts the host from an absolute URL, without a port, lower-cased.
  // Returns an empty string when the URL has no authority (`about:blank`,
  // `data:` URIs) so callers fall back to a letter avatar.
  static std::string HostForUrl(std::string_view url);

 private:
  struct Entry {
    std::string host;
    std::string png_base64;
  };

  void TouchLocked(std::unordered_map<std::string, std::list<Entry>::iterator>::iterator it);

  std::size_t capacity_;
  // Front is most recently used. `std::list` keeps iterators stable across
  // insertion and erase, which is what the index map depends on.
  std::list<Entry> entries_;
  std::unordered_map<std::string, std::list<Entry>::iterator> index_;
  mutable std::mutex mutex_;
};

}  // namespace kelpie
