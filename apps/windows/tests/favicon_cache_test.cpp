#include <cassert>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "favicon_cache.h"

using kelpie::windows::FaviconCache;
using kelpie::windows::TabIcon;

namespace {

// Real 32-bpp PNGs with a transparent first pixel, so the decode path, the
// premultiplied copy, and the alpha channel are all exercised for real rather
// than against a stub.
constexpr const char* kBluePng16 =
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUA"
    "AAAJcEhZcwAADsMAAA7DAcdvqGQAAAAfSURBVDhPY2BgYGDQqLjzn1xMkeZRA0YNGDVgMBkAAKZqeKQj0PGx"
    "AAAAAElFTkSuQmCC";
constexpr const char* kRedPng32 =
    "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUA"
    "AAAJcEhZcwAADsMAAA7DAcdvqGQAAAA0SURBVFhH7c4xEQAgEMCwykEE/lXgBQ4Vv2To3FR19rpTjc5/AAAA"
    "AAAAAAAAAAAAAAAADzCp+jrDxaHqAAAAAElFTkSuQmCC";

TabIcon Tab(const std::string& url, const char* png = kBluePng16) {
  TabIcon tab;
  tab.url = url;
  tab.favicon_png_base64 = png == nullptr ? std::string() : png;
  return tab;
}

// A deleted HBITMAP is no longer a valid GDI object, so GetObject fails on it.
// That is what proves eviction actually freed the handle rather than dropping
// the pointer.
bool IsLiveBitmap(HBITMAP bitmap) {
  BITMAP info{};
  return bitmap != nullptr && GetObject(bitmap, sizeof(info), &info) != 0;
}

void TestHostKeying() {
  assert(FaviconCache::HostForUrl("https://Example.COM:8443/a?b#c") == "example.com");
  assert(FaviconCache::HostForUrl("http://[2001:db8::1]:80/") == "[2001:db8::1]");
  assert(FaviconCache::HostForUrl("about:blank").empty());
  assert(FaviconCache::HostForUrl("kelpie://start") == "start");

  FaviconCache cache;
  assert(cache.Update(Tab("https://Example.com/one")));
  // Two URLs on one host share a single decoded bitmap.
  assert(cache.size() == 1);
  assert(cache.Peek("https://example.com/two") != nullptr);
  assert(cache.Peek("https://EXAMPLE.com/") == cache.Peek("https://example.com/"));
  assert(cache.Peek("https://other.test/") == nullptr);
}

void TestRejectsUnusableInput() {
  FaviconCache cache;
  // No host, no payload, and malformed base64 must all leave the cache empty.
  assert(!cache.Update(Tab("about:blank")));
  assert(!cache.Update(Tab("https://example.com/", nullptr)));
  assert(!cache.Update(Tab("https://example.com/", "not valid base64!!")));
  assert(!cache.Update(Tab("https://example.com/", "QUJD")));  // valid base64, not a PNG
  assert(!cache.Update(Tab("https://example.com/", "iVBORw0KGgo")));  // truncated quartet
  assert(cache.size() == 0);
}

void TestRepeatUpdateDoesNotReallocate() {
  FaviconCache cache;
  assert(cache.Update(Tab("https://example.com/")));
  HBITMAP first = cache.Peek("https://example.com/");
  assert(IsLiveBitmap(first));

  // Same payload: the entry is promoted, not decoded again.
  for (int iteration = 0; iteration < 20; ++iteration) {
    assert(cache.Update(Tab("https://example.com/")));
  }
  assert(cache.size() == 1);
  assert(cache.Peek("https://example.com/") == first);

  // A changed payload replaces the bitmap and releases the previous handle.
  assert(cache.Update(Tab("https://example.com/", kRedPng32)));
  HBITMAP second = cache.Peek("https://example.com/");
  assert(second != first);
  assert(IsLiveBitmap(second));
  assert(!IsLiveBitmap(first));
  assert(cache.size() == 1);
}

void TestEvictionFreesBitmaps() {
  FaviconCache cache(3);
  cache.Update(Tab("https://a.test/"));
  cache.Update(Tab("https://b.test/"));
  cache.Update(Tab("https://c.test/"));
  assert(cache.size() == 3);

  HBITMAP victim = cache.Peek("https://b.test/");
  assert(IsLiveBitmap(victim));

  // Touching a.test promotes it, leaving b.test least recently used.
  assert(cache.Lookup("https://a.test/") != nullptr);
  cache.Update(Tab("https://d.test/"));

  assert(cache.size() == 3);
  assert(cache.Peek("https://b.test/") == nullptr);
  // The evicted bitmap must be deleted, not merely forgotten: a leak here is a
  // process-wide GDI handle leak.
  assert(!IsLiveBitmap(victim));

  const std::vector<std::string> expected{"d.test", "a.test", "c.test"};
  assert(cache.HostsMostRecentFirst() == expected);

  // Peek leaves the order alone so painting cannot change eviction.
  cache.Peek("https://c.test/");
  assert(cache.HostsMostRecentFirst() == expected);
}

void TestBoundedGrowthAndClear() {
  // Warm up GDI+ and the GDI caches so the measurement below sees only the
  // handles this code owns.
  {
    FaviconCache warmup(2);
    warmup.Update(Tab("https://warmup.test/"));
  }
  const DWORD before = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  {
    FaviconCache cache(8);
    for (int index = 0; index < 200; ++index) {
      cache.Update(Tab("https://host" + std::to_string(index) + ".test/"));
    }
    assert(cache.size() == 8);

    std::vector<HBITMAP> live;
    for (const std::string& host : cache.HostsMostRecentFirst()) {
      live.push_back(cache.Peek("https://" + host + "/"));
    }
    cache.Clear();
    assert(cache.size() == 0);
    for (HBITMAP bitmap : live) {
      assert(!IsLiveBitmap(bitmap));
    }

    // A zero capacity clamps to one rather than making every store a no-op.
    FaviconCache degenerate(0);
    assert(degenerate.capacity() == 1);
    degenerate.Update(Tab("https://a.test/"));
    degenerate.Update(Tab("https://b.test/"));
    assert(degenerate.size() == 1);
  }
  // 200 decodes and two destructors later, the process must be back where it
  // started: every bitmap the cache made is a handle it had to delete.
  const DWORD after = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  assert(after <= before);
}

void TestDrawTabIconFallbacks() {
  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP surface = CreateCompatibleBitmap(screen, 32, 32);
  HGDIOBJ previous = SelectObject(memory, surface);
  const RECT bounds{0, 0, 14, 14};

  FaviconCache cache;
  TabIcon start = Tab("kelpie://start", nullptr);
  start.is_start_page = true;

  const auto paint_every_path = [&] {
    // The start page star wins over everything, matching macOS, and is never
    // cached as a favicon.
    DrawTabIcon(memory, bounds, start, cache);
    // A host with no favicon falls back to the letter avatar and caches nothing.
    DrawTabIcon(memory, bounds, Tab("https://avatar.test/", nullptr), cache);
    // A favicon on the snapshot is decoded on first paint and reused after.
    DrawTabIcon(memory, bounds, Tab("https://example.com/"), cache);
  };

  // Warm up all three branches. GDI grows its own font and brush caches over the
  // first few paints and settles at a steady state; that one-off growth is not a
  // leak, so it is not what gets measured.
  for (int iteration = 0; iteration < 10; ++iteration) {
    paint_every_path();
  }
  assert(cache.size() == 1);
  cache.Clear();

  const auto measured_round = [&] {
    for (int iteration = 0; iteration < 30; ++iteration) {
      paint_every_path();
    }
    // The favicon is decoded once and reused for the other 29 passes, and the
    // avatar and star branches cache nothing.
    assert(cache.size() == 1);
    const DWORD used = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
    cache.Clear();
    return used;
  };

  // Two identical rounds must consume identical handles. A leak in any of the
  // three branches would make the second round higher than the first.
  const DWORD first = measured_round();
  const DWORD second = measured_round();
  assert(second <= first);

  SelectObject(memory, previous);
  DeleteObject(surface);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
}

}  // namespace

int main() {
  // A failed assert must print and exit, never raise the CRT's modal dialog:
  // under CTest that dialog hangs the run instead of failing it.
#if defined(_MSC_VER)
  _set_error_mode(_OUT_TO_STDERR);
  _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
#endif

  TestHostKeying();
  TestRejectsUnusableInput();
  TestRepeatUpdateDoesNotReallocate();
  TestEvictionFreesBitmaps();
  TestBoundedGrowthAndClear();
  TestDrawTabIconFallbacks();
  std::cout << "favicon cache tests passed" << std::endl;
  return 0;
}
