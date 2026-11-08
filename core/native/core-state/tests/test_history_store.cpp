#include "kelpie/history_store.h"
#include "kelpie/state_c_api.h"

#include <cassert>
#include <iostream>

#include <nlohmann/json.hpp>

namespace {

using json = nlohmann::json;

void TestEmptyAndClear() {
  kelpie::HistoryStore store;
  assert(store.Count() == 0);
  store.Clear();
  assert(json::parse(store.ToJson()).empty());
}

void TestDedupAndLatestTitleUpdate() {
  kelpie::HistoryStore store;
  store.Record("https://one.test", "One");
  store.Record("https://two.test", "Two");
  // Revisiting one.test should remove the earlier entry and move it to top.
  store.Record("https://one.test", "One Again");
  store.UpdateLatestTitle("https://one.test", "   One Updated   ");
  store.UpdateLatestTitle("https://two.test", "Should not apply");

  const json entries = json::parse(store.ToJson());
  assert(entries.size() == 2);
  assert(entries[0]["url"] == "https://one.test");
  assert(entries[0]["title"] == "One Updated");
  assert(entries[1]["url"] == "https://two.test");
}

void TestCapacityAndLoadJson() {
  kelpie::HistoryStore store;
  for (int index = 0; index < 505; ++index) {
    store.Record("https://site.test/" + std::to_string(index), "Page " + std::to_string(index));
  }
  assert(store.Count() == 500);

  const json entries = json::parse(store.ToJson());
  assert(entries[0]["url"] == "https://site.test/504");
  assert(entries.back()["url"] == "https://site.test/5");

  store.LoadJson(R"([
    {"id":"1","url":"https://loaded.test","title":"Loaded","timestamp":"2026-04-01T12:00:00Z"},
    {"id":"2","url":"https://loaded-two.test","title":"Loaded Two","timestamp":"2026-04-01T12:01:00Z"}
  ])");
  assert(store.Count() == 2);

  store.LoadJson("{]");
  assert(store.Count() == 0);
}

void TestUrlNormalizationDedup() {
  kelpie::HistoryStore store;
  // Bare-origin slash variant collapses.
  store.Record("https://norm.test/", "One");
  store.Record("https://norm.test", "One Too");
  // Empty query collapses.
  store.Record("https://norm.test?", "Three");
  store.Record("https://norm.test", "Three Too");
  // Empty fragment collapses.
  store.Record("https://norm.test#", "Four");
  store.Record("https://norm.test", "Four Too");
  // All combined.
  store.Record("https://norm.test/?#", "Five");
  store.Record("https://norm.test", "Five Too");

  const json entries = json::parse(store.ToJson());
  // Should have exactly one entry per base URL (norm.test), all with final title.
  assert(entries.size() == 1);
  assert(entries[0]["url"] == "https://norm.test");
  assert(entries[0]["title"] == "Five Too");

  // Root "/" vs no slash must both be stored as-is since they normalize to the
  // same key but we preserve the original URL.
  kelpie::HistoryStore store2;
  store2.Record("https://root.test/", "Root slash");
  store2.Record("https://root.test", "Root no slash");
  const json root_entries = json::parse(store2.ToJson());
  assert(root_entries.size() == 1);
  assert(root_entries[0]["url"] == "https://root.test");
  assert(root_entries[0]["title"] == "Root no slash");

  // Resource paths keep their trailing slash because /docs and /docs/ can be
  // different resources on real servers.
  kelpie::HistoryStore path_store;
  path_store.Record("https://path.test/docs/", "Docs slash");
  path_store.Record("https://path.test/docs", "Docs no slash");
  const json path_entries = json::parse(path_store.ToJson());
  assert(path_entries.size() == 2);
  assert(path_entries[0]["url"] == "https://path.test/docs");
  assert(path_entries[1]["url"] == "https://path.test/docs/");
}

void TestCApiRoundTrip() {
  KelpieHistoryStoreRef store = kelpie_history_store_create();
  assert(store != nullptr);

  kelpie_history_store_record(store, "https://ffi.test/1", "One");
  kelpie_history_store_record(store, "https://ffi.test/2", "Two");
  // Revisit /1 — should move to top, leaving only 2 entries.
  kelpie_history_store_record(store, "https://ffi.test/1", "One Again");
  kelpie_history_store_update_latest_title(store, "https://ffi.test/1", "  Updated One  ");

  char* payload = kelpie_history_store_to_json(store);
  assert(payload != nullptr);
  const json entries = json::parse(payload);
  kelpie_free_string(payload);
  assert(entries.size() == 2);
  assert(entries[0]["url"] == "https://ffi.test/1");
  assert(entries[0]["title"] == "Updated One");

  kelpie_history_store_destroy(store);
}

void TestBestUrlCompletion() {
  kelpie::HistoryStore legacy;
  legacy.Record("https://github/", "Web page not available");
  assert(legacy.BestUrlCompletion("GitHub").empty());
  assert(legacy.BestUrlCompletion("https://git") == "https://github/");
  legacy.Record("http://localhost:8420/page", "Local");
  assert(legacy.BestUrlCompletion("local") == "http://localhost:8420/page");
  legacy.Record("http://192.168.1.215/", "LAN");
  assert(legacy.BestUrlCompletion("192.168") == "http://192.168.1.215/");
  legacy.Record("https://github.com/", "GitHub");
  assert(legacy.BestUrlCompletion("GitHub") == "https://github.com/");
  kelpie::HistoryStore store;
  store.Record("https://www.deepwater.example/path", "Deep Water");
  store.Record("https://second.example", "Second");

  assert(store.BestUrlCompletion("https://www.deep") == "https://www.deepwater.example/path");
  assert(store.BestUrlCompletion("www.deep") == "https://www.deepwater.example/path");
  assert(store.BestUrlCompletion("deepwater") == "https://www.deepwater.example/path");
  assert(store.BestUrlCompletion("deep water") == "https://www.deepwater.example/path");
  assert(store.BestUrlCompletion("missing").empty());

  KelpieHistoryStoreRef ffi_store = kelpie_history_store_create();
  assert(ffi_store != nullptr);
  kelpie_history_store_record(ffi_store, "https://www.deepwater.example/path", "Deep Water");
  char* completion = kelpie_history_store_best_url_completion(ffi_store, "deepwater");
  assert(completion != nullptr);
  assert(std::string(completion) == "https://www.deepwater.example/path");
  kelpie_free_string(completion);
  kelpie_history_store_destroy(ffi_store);
}

}  // namespace

int main() {
  try {
    TestEmptyAndClear();
    TestDedupAndLatestTitleUpdate();
    TestCapacityAndLoadJson();
    TestUrlNormalizationDedup();
    TestCApiRoundTrip();
    TestBestUrlCompletion();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
