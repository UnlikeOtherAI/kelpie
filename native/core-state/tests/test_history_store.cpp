#include "mollotov/history_store.h"
#include "mollotov/state_c_api.h"

#include <cassert>
#include <iostream>

#include <nlohmann/json.hpp>

namespace {

using json = nlohmann::json;

void TestEmptyAndClear() {
  mollotov::HistoryStore store;
  assert(store.Count() == 0);
  store.Clear();
  assert(json::parse(store.ToJson()).empty());
}

void TestDedupAndLatestTitleUpdate() {
  mollotov::HistoryStore store;
  store.Record("https://one.test", "One");
  store.Record("https://one.test", "Ignored duplicate");
  store.Record("https://two.test", "Two");
  store.UpdateLatestTitle("https://two.test", "   Updated Two   ");
  store.UpdateLatestTitle("https://one.test", "Should not apply");

  const json entries = json::parse(store.ToJson());
  assert(entries.size() == 2);
  assert(entries[0]["url"] == "https://two.test");
  assert(entries[0]["title"] == "Updated Two");
  assert(entries[1]["url"] == "https://one.test");
}

void TestCapacityAndLoadJson() {
  mollotov::HistoryStore store;
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

void TestCApiRoundTrip() {
  MollotovHistoryStoreRef store = mollotov_history_store_create();
  assert(store != nullptr);

  mollotov_history_store_record(store, "https://ffi.test/1", "One");
  mollotov_history_store_record(store, "https://ffi.test/1", "Duplicate ignored");
  mollotov_history_store_record(store, "https://ffi.test/2", "Two");
  mollotov_history_store_update_latest_title(store, "https://ffi.test/2", "  Updated Two  ");

  char* payload = mollotov_history_store_to_json(store);
  assert(payload != nullptr);
  const json entries = json::parse(payload);
  mollotov_free_string(payload);
  assert(entries.size() == 2);
  assert(entries[0]["title"] == "Updated Two");

  mollotov_history_store_destroy(store);
}

}  // namespace

int main() {
  try {
    TestEmptyAndClear();
    TestDedupAndLatestTitleUpdate();
    TestCapacityAndLoadJson();
    TestCApiRoundTrip();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
