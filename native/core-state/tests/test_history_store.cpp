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
  // Trailing slash variant collapses.
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

}  // namespace

int main() {
  try {
    TestEmptyAndClear();
    TestDedupAndLatestTitleUpdate();
    TestCapacityAndLoadJson();
    TestUrlNormalizationDedup();
    TestCApiRoundTrip();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
