#include <atomic>
#include <cassert>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#include "kelpie/desktop_browser_control.h"
#include "kelpie/site_preview_capture.h"
#include "kelpie/site_preview_store.h"
#include "site_preview_image.h"

namespace {

using namespace kelpie;
using namespace kelpie::site_preview;

void TestCrop() {
  // 16:9 is wider than the card: full height, sides trimmed equally.
  const PixelRect wide = PreviewCrop(1920, 1080);
  assert(wide.width == 1728 && wide.height == 1080 && wide.x == 96 && wide.y == 0);
  // A tall viewport keeps the full width and the top of the page.
  const PixelRect tall = PreviewCrop(1280, 1400);
  assert(tall.width == 1280 && tall.height == 800 && tall.x == 0 && tall.y == 0);
  const PixelRect exact = PreviewCrop(1600, 1000);
  assert(exact.width == 1600 && exact.height == 1000);
  assert(PreviewCrop(0, 100).width == 0);

  // Large crops scale to the preview size; small ones are never upscaled.
  const PixelRect scaled = PreviewSize(wide);
  assert(scaled.width == kPreviewWidth && scaled.height == kPreviewHeight);
  const PixelRect small = PreviewSize(PreviewCrop(320, 200));
  assert(small.width == 320 && small.height == 200);
}

void TestDownscale() {
  // A 4x2 image: the left 2x2 block is black, the right 2x2 block is white.
  std::vector<std::uint8_t> pixels(4 * 2 * 4, 0);
  for (int y = 0; y < 2; ++y) {
    for (int x = 2; x < 4; ++x) {
      for (int c = 0; c < 4; ++c) pixels[(y * 4 + x) * 4 + c] = 255;
    }
  }
  const auto halved = Downscale(pixels, 4, 2, {0, 0, 4, 2}, 2, 1);
  assert(halved.size() == 2 * 4);
  assert(halved[0] == 0 && halved[4] == 255);
  // The whole image averages to mid grey.
  const auto single = Downscale(pixels, 4, 2, {0, 0, 4, 2}, 1, 1);
  assert(single.size() == 4 && single[0] == 128);
  // A crop selects only its own pixels.
  const auto right = Downscale(pixels, 4, 2, {2, 0, 2, 2}, 1, 1);
  assert(right[0] == 255);
  // Out-of-bounds crops, upscaling and mismatched buffers are refused.
  assert(Downscale(pixels, 4, 2, {3, 0, 2, 2}, 1, 1).empty());
  assert(Downscale(pixels, 4, 2, {0, 0, 4, 2}, 8, 4).empty());
  assert(Downscale(std::vector<std::uint8_t>(5), 4, 2, {0, 0, 4, 2}, 1, 1).empty());
}

void TestBlank() {
  std::vector<std::uint8_t> white(16 * 16 * 4, 250);
  assert(LooksBlank(white, 16, 16));
  // A small dark logo on a white page is a real page.
  for (int c = 0; c < 3; ++c) white[(5 * 16 + 5) * 4 + c] = 20;
  assert(!LooksBlank(white, 16, 16));
  assert(LooksBlank({}, 0, 0));
}

void TestBase64() {
  const auto abc = DecodeBase64("QUJD");
  assert(abc && std::string(abc->begin(), abc->end()) == "ABC");
  const auto ab = DecodeBase64("QUI=");
  assert(ab && std::string(ab->begin(), ab->end()) == "AB");
  const auto a = DecodeBase64("QQ==");
  assert(a && std::string(a->begin(), a->end()) == "A");
  assert(DecodeBase64("")->empty());
  assert(!DecodeBase64("QUJ"));
  assert(!DecodeBase64("Q=JD"));
  assert(!DecodeBase64("QU!D"));
}

void TestKeys() {
  assert(SitePreviewStore::KeyForHost("Example.COM") == "6578616d706c652e636f6d");
  assert(SitePreviewStore::HostForKey("6578616d706c652e636f6d") == std::optional<std::string>("example.com"));
  // Anything that could escape the store, or is not a plausible host, is refused.
  assert(!SitePreviewStore::HostForKey(SitePreviewStore::KeyForHost("../secret")));
  assert(!SitePreviewStore::HostForKey("2e2e2f"));
  assert(!SitePreviewStore::HostForKey("6578616D"));
  assert(!SitePreviewStore::HostForKey("657"));
  assert(!SitePreviewStore::HostForKey(""));
  assert(SitePreviewStore::HostForKey(SitePreviewStore::KeyForHost("[::1]")) == std::optional<std::string>("[::1]"));
}

void TestMemoryStore() {
  SitePreviewStore store({}, 2);
  assert(!store.StoreThumbnail("", "x"));
  assert(!store.StoreThumbnail("a.test", ""));
  assert(!store.StoreThumbnail("bad/host", "x"));
  assert(store.StoreThumbnail("A.test", "one"));
  assert(store.Thumbnail("a.test") == std::optional<std::string>("one"));
  const auto first = store.ThumbnailVersion("a.test");
  assert(store.StoreThumbnail("a.test", "two"));
  assert(*store.ThumbnailVersion("a.test") > *first);
  assert(store.StoreFavicon("a.test", "icon"));
  assert(store.Favicon("a.test") == std::optional<std::string>("icon"));
  assert(!store.Favicon("b.test"));
  assert(!store.ThumbnailVersion("b.test"));

  // Capacity evicts the least recently captured host.
  store.StoreThumbnail("b.test", "b");
  store.StoreThumbnail("c.test", "c");
  assert(store.size() == 2 && !store.Thumbnail("a.test") && store.Thumbnail("c.test"));

  store.RetainOnly({"c.test"});
  assert(store.size() == 1 && !store.Thumbnail("b.test"));
}

void TestDiskStore() {
  const auto directory = std::filesystem::temp_directory_path() /
      ("kelpie-site-preview-test-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  {
    SitePreviewStore store(directory);
    assert(store.StoreThumbnail("first.test", "jpeg-1"));
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    assert(store.StoreThumbnail("second.test", "jpeg-2"));
    assert(store.StoreFavicon("second.test", "png-2"));
    assert(std::filesystem::exists(directory / (SitePreviewStore::KeyForHost("first.test") + ".jpg")));
  }
  // An interrupted write and an unrelated file are cleaned up or ignored.
  { std::ofstream(directory / "deadbeef.jpg.tmp") << "partial"; }
  { std::ofstream(directory / "notes.txt") << "ignored"; }
  {
    SitePreviewStore store(directory);
    assert(store.size() == 2);
    assert(store.Thumbnail("first.test") == std::optional<std::string>("jpeg-1"));
    assert(store.Favicon("second.test") == std::optional<std::string>("png-2"));
    // Reload keeps capture order: the later host has the higher version.
    assert(*store.ThumbnailVersion("second.test") > *store.ThumbnailVersion("first.test"));
    assert(!std::filesystem::exists(directory / "deadbeef.jpg.tmp"));
    store.RetainOnly({"second.test"});
    assert(!std::filesystem::exists(directory / (SitePreviewStore::KeyForHost("first.test") + ".jpg")));
  }
  std::error_code error;
  std::filesystem::remove_all(directory, error);
}

// Answers only what the capture worker asks: the tab list and the capture.
class FakeBrowser final : public DesktopBrowserControl {
 public:
  std::mutex mutex;
  std::vector<TabSnapshot> tabs;
  std::string captured_url;
  std::atomic<int> captures{0};

  BrowserControlResult GetTabs(std::vector<TabSnapshot>* out, Timeout) override {
    std::lock_guard<std::mutex> lock(mutex);
    *out = tabs;
    return BrowserControlResult::Success();
  }
  BrowserControlResult CaptureSitePreview(TabLease, Json* out, Timeout) override {
    std::lock_guard<std::mutex> lock(mutex);
    ++captures;
    *out = {{"url", captured_url}, {"data", "QUJD"}};
    return BrowserControlResult::Success();
  }
  BrowserControlResult ResolveTab(const std::optional<std::string>&, const std::optional<std::uint64_t>&,
                                  TabLease*, Timeout) override { return Unused(); }
  BrowserControlResult CreateTab(const NewTabRequest&, TabSnapshot*, Timeout) override { return Unused(); }
  BrowserControlResult ActivateTab(TabLease, Timeout) override { return Unused(); }
  BrowserControlResult CloseTab(TabLease, Timeout) override { return Unused(); }
  BrowserControlResult Navigate(std::optional<TabLease>, std::string, TabSnapshot*, Timeout) override { return Unused(); }
  BrowserControlResult Back(TabLease, TabSnapshot*, Timeout) override { return Unused(); }
  BrowserControlResult Forward(TabLease, TabSnapshot*, Timeout) override { return Unused(); }
  BrowserControlResult Reload(TabLease, TabSnapshot*, Timeout) override { return Unused(); }
  BrowserControlResult Evaluate(TabLease, std::string, Json*, Timeout) override { return Unused(); }
  BrowserControlResult Screenshot(TabLease, BrowserScreenshot*, Timeout) override { return Unused(); }
  BrowserControlResult GetCookies(TabLease, const Json&, Json*, Timeout) override { return Unused(); }
  BrowserControlResult SetCookies(TabLease, const Json&, Json*, Timeout) override { return Unused(); }
  BrowserControlResult DeleteCookies(TabLease, const Json&, Json*, Timeout) override { return Unused(); }
  BrowserControlResult DispatchTrustedInput(TabLease, const Json&, Json*, Timeout) override { return Unused(); }
  BrowserControlResult GetDialog(TabLease, Json*, Timeout) override { return Unused(); }
  BrowserControlResult HandleDialog(TabLease, const Json&, Json*, Timeout) override { return Unused(); }
  BrowserControlResult DevTools(TabLease, std::string, const Json&, Json*, Timeout) override { return Unused(); }

  void Show(TabSnapshot tab) {
    std::lock_guard<std::mutex> lock(mutex);
    tabs = {std::move(tab)};
    captured_url = tabs.front().url;
  }

 private:
  static BrowserControlResult Unused() { return BrowserControlResult::Failure("UNUSED", "not used"); }
};

TabSnapshot ActiveTab(std::string url) {
  TabSnapshot tab;
  tab.id = "tab-1";
  tab.generation = 1;
  tab.url = std::move(url);
  tab.active = true;
  return tab;
}

template <typename Predicate>
bool Eventually(Predicate predicate) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  while (std::chrono::steady_clock::now() < deadline) {
    if (predicate()) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  return predicate();
}

void TestCapture() {
  FakeBrowser browser;
  SitePreviewStore store;
  std::atomic<std::uint64_t> generation{0};
  SitePreviewCapture::Options options;
  options.settle = std::chrono::milliseconds(10);
  options.poll = std::chrono::milliseconds(10);
  options.refresh = std::chrono::hours(1);
  SitePreviewCapture capture(
      browser, store, [](const std::string& data) { return std::optional<std::string>("jpeg:" + data); },
      [] { return std::unordered_set<std::string>{"keep.test"}; }, [&generation] { return generation.load(); },
      options);
  capture.Start();

  // A settled web page is captured with its favicon.
  TabSnapshot page = ActiveTab("https://Example.test/path");
  page.favicon_png_base64 = std::make_shared<const std::string>("QUJD");
  browser.Show(page);
  capture.NotifyNavigation();
  assert(Eventually([&] { return store.Thumbnail("example.test").has_value(); }));
  assert(store.Thumbnail("example.test") == std::optional<std::string>("jpeg:QUJD"));
  assert(store.Favicon("example.test") == std::optional<std::string>("ABC"));

  // The same host is not captured again inside the refresh interval.
  const int after_first = browser.captures.load();
  capture.NotifyNavigation();
  std::this_thread::sleep_for(std::chrono::milliseconds(80));
  assert(browser.captures.load() == after_first);

  // Start pages, loading pages, other schemes and in-memory partitions are skipped.
  TabSnapshot start = ActiveTab("kelpie://start");
  start.is_start_page = true;
  TabSnapshot loading = ActiveTab("https://loading.test/");
  loading.is_loading = true;
  TabSnapshot isolated = ActiveTab("https://private.test/");
  isolated.partition = "scratch";
  isolated.persistent = false;
  for (const TabSnapshot& skipped : {start, loading, ActiveTab("file:///C:/x.html"), isolated}) {
    browser.Show(skipped);
    capture.NotifyNavigation();
    std::this_thread::sleep_for(std::chrono::milliseconds(60));
  }
  assert(browser.captures.load() == after_first);
  assert(!store.Thumbnail("private.test"));

  // A capture that ends on a different site is discarded.
  browser.Show(ActiveTab("https://moved.test/"));
  {
    std::lock_guard<std::mutex> lock(browser.mutex);
    browser.captured_url = "https://elsewhere.test/";
  }
  capture.NotifyNavigation();
  assert(Eventually([&] { return browser.captures.load() > after_first; }));
  std::this_thread::sleep_for(std::chrono::milliseconds(30));
  assert(!store.Thumbnail("moved.test") && !store.Thumbnail("elsewhere.test"));

  // Clearing history keeps only the favourites' screenshots.
  store.StoreThumbnail("keep.test", "kept");
  ++generation;
  assert(Eventually([&] { return !store.Thumbnail("example.test").has_value(); }));
  assert(store.Thumbnail("keep.test").has_value());

  capture.BeginStop();
  assert(Eventually([&] { return capture.IsStopped(); }));
  capture.Join();
}

}  // namespace

int main() {
  TestCrop();
  TestDownscale();
  TestBlank();
  TestBase64();
  TestKeys();
  TestMemoryStore();
  TestDiskStore();
  TestCapture();
  std::cout << "site preview tests passed" << std::endl;
  return 0;
}
