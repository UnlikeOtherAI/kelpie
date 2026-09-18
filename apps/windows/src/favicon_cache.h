#pragma once

#include <cstddef>
#include <list>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "letter_avatar.h"

namespace kelpie::windows {

// What the tab strip knows about one tab's icon. The three fields map straight
// onto `kelpie::TabSnapshot`.
struct TabIcon {
  // `TabSnapshot::url`. Only its host is used, as the cache key.
  std::string url;
  // `TabSnapshot::favicon_png_base64`, or empty when the engine has not
  // downloaded one yet.
  std::string favicon_png_base64;
  // `TabSnapshot::is_start_page`.
  bool is_start_page = false;
};

// Host-keyed cache of decoded favicons, bounded and LRU.
//
// Each entry owns an `HBITMAP`, so eviction must delete it — a leak here is a
// GDI handle leak, which is process-wide and unrecoverable. `kelpie_windows_
// favicon_cache_test` asserts the evicted handle is actually gone.
//
// The cache initialises GDI+ itself on first construction and shuts it down when
// the last instance is destroyed, so no caller has to remember to do it.
//
// Not thread-safe: GDI objects belong to the UI thread and everything here is
// called from the tab strip's window procedure.
class FaviconCache {
 public:
  // 32 tabs' worth of icons is well past any realistic strip.
  static constexpr std::size_t kDefaultCapacity = 32;

  explicit FaviconCache(std::size_t capacity = kDefaultCapacity);
  ~FaviconCache();

  // Owns GDI handles; copying would double-free them.
  FaviconCache(const FaviconCache&) = delete;
  FaviconCache& operator=(const FaviconCache&) = delete;

  // Decodes `tab.favicon_png_base64` and caches it under the tab's host.
  //
  // Idempotent and cheap to call on every tab refresh: a payload identical to
  // the cached one only promotes the entry, and an empty payload, an unusable
  // host, or an undecodable PNG leaves the cache untouched. Returns true when
  // the host now has a bitmap.
  bool Update(const TabIcon& tab);

  // The bitmap for this URL's host, or nullptr. Promotes the entry.
  HBITMAP Lookup(std::string_view url);

  // Read-only probe that leaves the recency order alone.
  HBITMAP Peek(std::string_view url) const;

  // Deletes every cached bitmap.
  void Clear();

  std::size_t size() const { return entries_.size(); }
  std::size_t capacity() const { return capacity_; }

  // Most-recently-used first. For tests.
  std::vector<std::string> HostsMostRecentFirst() const;

  // The cache key: the lower-cased host of `url`, empty when it has none.
  static std::string HostForUrl(std::string_view url);

 private:
  struct Entry {
    std::string host;
    // The base64 payload this bitmap was decoded from, so a repeat Update with
    // unchanged bytes skips the decode.
    std::string source;
    HBITMAP bitmap = nullptr;
    int width = 0;
    int height = 0;
  };

  void EraseLocked(std::list<Entry>::iterator entry);

  std::size_t capacity_;
  // Front is most recently used; `std::list` keeps the index's iterators valid.
  std::list<Entry> entries_;
  std::unordered_map<std::string, std::list<Entry>::iterator> index_;
};

// Paints the 14 DIP tab icon for `tab` into `bounds`.
//
// This is the single entry point the tab strip needs: it caches the tab's
// favicon if it is new, then paints, in the same precedence as
// `TabPillView.refreshContent()` on macOS — the start page star when
// `tab.is_start_page`, otherwise the favicon when one is cached, otherwise the
// letter avatar.
//
// `bounds` should be `LetterAvatarSize(hwnd)` square.
void DrawTabIcon(HDC device_context, const RECT& bounds, const TabIcon& tab, FaviconCache& cache);

}  // namespace kelpie::windows
