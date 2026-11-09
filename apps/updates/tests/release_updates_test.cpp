#ifdef _WIN32
#include <windows.h>
#endif
#include "../release_monitor.h"
#include <cassert>
#include <thread>

using namespace kelpie::updates;
using json = nlohmann::json;
json Entry(std::string version = "0.2.1", std::string target = "windows-x64") {
  return {{"draft", false}, {"prerelease", false}, {"body", std::string(kMarker) +
      json{{"target", target}, {"version", version}, {"url",
        "https://github.com/UnlikeOtherAI/kelpie/releases/download/release/2026-11-09/kelpie.zip"},
        {"sha256", std::string(64, 'a')}}.dump() + " -->"}};
}
std::optional<Release> Complete(ReleaseMonitor& monitor, ReleaseMonitor::Clock::time_point now) {
  monitor.Tick(now);
  for (int i = 0; i < 2000; ++i) {
    auto result = monitor.Tick(now);
    if (result) return result;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return std::nullopt;
}
int main() {
  auto feed = json::array({Entry()});
  assert(FindRelease(feed.dump(), "windows-x64", "0.2.0")->version == "0.2.1");
  assert(!FindRelease(feed.dump(), "macos-arm64", "0.2.0"));
  assert(!FindRelease(feed.dump(), "windows-x64", "0.2.1"));
  assert(!FindRelease(feed.dump(), "windows-x64", "0.3.0"));
  assert(!FindRelease(feed.dump(), "windows-x64", "invalid"));
  assert(!FindRelease("invalid", "windows-x64", "0.2.0"));
  assert(!FindRelease("{}", "windows-x64", "0.2.0"));
  for (const char* property : {"draft", "prerelease"}) {
    auto hidden = feed; hidden[0][property] = true;
    assert(!FindRelease(hidden.dump(), "windows-x64", "0.2.0"));
  }
  assert(FindRelease(json::array({Entry("0.2.9"), Entry("0.2.10"), Entry("0.2.2")}).dump(),
      "windows-x64", "0.2.0")->version == "0.2.10");
  auto malformed = Entry(); malformed["body"] = "<!-- kelpie-update: {broken} -->";
  assert(FindRelease(json::array({malformed, Entry()}).dump(), "windows-x64", "0.2.0"));
  assert(!SafeURL("https://github.com.evil.example/UnlikeOtherAI/kelpie/releases/download/a.zip", "windows-x64"));
  assert(!SafeURL("file:///tmp/update.zip", "windows-x64"));
  assert(!Version("1.2.9999999"));

  auto directory = std::filesystem::temp_directory_path() / ("kelpie-update-test-" +
      std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  std::filesystem::create_directory(directory);
  const auto preferences = directory / "skipped.json";
  const auto now = ReleaseMonitor::Clock::now();
  auto fetch = [&] { return feed.dump(); };
  {
    ReleaseMonitor monitor("windows-x64", "0.2.0", preferences, fetch);
    assert(Complete(monitor, now));
    assert(!Complete(monitor, now + std::chrono::hours(7))); // Not now lasts this launch only.
  }
  {
    ReleaseMonitor restarted("windows-x64", "0.2.0", preferences, fetch);
    auto release = Complete(restarted, now);
    assert(release); // The next launch asks again.
    assert(restarted.Skip(*release));
  }
  {
    ReleaseMonitor restarted("windows-x64", "0.2.0", preferences, fetch);
    assert(!Complete(restarted, now)); // Skip survives process restart.
    feed.push_back(Entry("0.2.2"));
    assert(Complete(restarted, now + std::chrono::hours(7))->version == "0.2.2");
  }
  {
    int calls = 0;
    ReleaseMonitor offline("windows-x64", "0.2.0", preferences, [&] {
      if (++calls == 1) throw std::runtime_error("offline");
      return feed.dump();
    });
    assert(!Complete(offline, now));
    assert(Complete(offline, now + std::chrono::minutes(16))); // Self-heals without deleting state.
  }
  std::filesystem::remove_all(directory);
}
