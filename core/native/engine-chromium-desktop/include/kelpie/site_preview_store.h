#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>

namespace kelpie {

// What the start page shows for a site: a screenshot and the site's favicon,
// keyed by host and kept across launches.
//
// Each host owns up to two files in `directory`, named after the host's hex
// key: `<key>.jpg` holds the preview JPEG and `<key>.png` the favicon PNG. Hex
// keeps every host a safe file name and a safe URL path segment, and decodes
// back to the host without a separate index. The store is a bounded LRU by
// capture order, and an empty directory makes it memory-only, which is what a
// profile-less test shell wants. Every method is safe to call from any thread:
// the capture worker writes while the CEF IO thread reads for `kelpie://start`.
class SitePreviewStore {
 public:
  static constexpr std::size_t kDefaultCapacity = 96;

  explicit SitePreviewStore(std::filesystem::path directory = {},
                            std::size_t capacity = kDefaultCapacity);

  // Replaces the host's screenshot. Ignores an empty host or payload so a
  // failed capture cannot evict a good preview. Returns false when ignored or
  // when the file could not be written.
  bool StoreThumbnail(const std::string& host, std::string jpeg);
  // Replaces the host's favicon with raw PNG bytes; same rules as above.
  bool StoreFavicon(const std::string& host, std::string png);

  // Raw JPEG and PNG bytes, or nullopt when the host has none.
  std::optional<std::string> Thumbnail(const std::string& host) const;
  std::optional<std::string> Favicon(const std::string& host) const;
  // Increments every time the host's screenshot changes; the start page puts
  // it in the preview URL so a new capture is never shown from a stale image.
  std::optional<std::uint64_t> ThumbnailVersion(const std::string& host) const;

  // Deletes every host not in `hosts`. Called with the hosts of the current
  // favourites and history, so clearing history clears its screenshots too.
  void RetainOnly(const std::unordered_set<std::string>& hosts);
  std::size_t size() const;

  // The lower-case hex encoding of a lower-cased host, and its inverse. The
  // inverse returns nullopt for anything that is not even-length lower-case hex
  // of a plausible host, which is what makes it safe on a request path.
  static std::string KeyForHost(std::string_view host);
  static std::optional<std::string> HostForKey(std::string_view key);

 private:
  struct Entry {
    std::uint64_t order = 0;
    std::uint64_t thumbnail_version = 0;
    bool has_thumbnail = false;
    bool has_favicon = false;
    std::string thumbnail;  // Memory-only stores keep the bytes here.
    std::string favicon;
  };

  void LoadLocked();
  bool WriteLocked(const std::string& host, std::string_view extension, const std::string& bytes);
  std::optional<std::string> ReadLocked(const std::string& host, std::string_view extension) const;
  void EraseLocked(const std::string& host);
  void EvictLocked();

  std::filesystem::path directory_;
  std::size_t capacity_;
  std::uint64_t next_order_ = 1;
  std::unordered_map<std::string, Entry> entries_;
  mutable std::mutex mutex_;
};

}  // namespace kelpie
