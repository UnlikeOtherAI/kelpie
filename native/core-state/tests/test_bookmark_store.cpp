#include "kelpie/bookmark_store.h"
#include "kelpie/state_c_api.h"

#include <cassert>
#include <iostream>

#include <nlohmann/json.hpp>

namespace {

using json = nlohmann::json;

void TestEmptyStore() {
  kelpie::BookmarkStore store;
  assert(store.Count() == 0);
  assert(json::parse(store.ToJson()).empty());
}

void TestAddRemoveAndClear() {
  kelpie::BookmarkStore store;
  store.Add("Example", "https://example.com");
  store.Add("Docs", "https://docs.example.com");

  const json entries = json::parse(store.ToJson());
  assert(entries.size() == 2);
  assert(entries[0]["title"] == "Example");
  assert(entries[0].contains("created_at"));

  store.Remove(entries[0]["id"].get<std::string>());
  assert(store.Count() == 1);

  store.RemoveAll();
  assert(store.Count() == 0);
  assert(json::parse(store.ToJson()).empty());
}

void TestLoadJsonRoundTripAndInvalidInput() {
  kelpie::BookmarkStore store;
  store.LoadJson(R"([
    {"id":"a","title":"One","url":"https://one.test","created_at":"2026-04-01T12:00:00Z"},
    {"id":"b","title":"Two","url":"https://two.test","createdAt":"2026-04-01T12:01:00Z"},
    {"id":"bad","title":"","url":""}
  ])");

  const json entries = json::parse(store.ToJson());
  assert(entries.size() == 2);
  assert(entries[1]["created_at"] == "2026-04-01T12:01:00Z");

  store.LoadJson("not json");
  assert(store.Count() == 0);
}

void TestCApiRoundTrip() {
  KelpieBookmarkStoreRef store = kelpie_bookmark_store_create();
  assert(store != nullptr);

  kelpie_bookmark_store_add(store, "API", "https://ffi.test");
  assert(kelpie_bookmark_store_count(store) == 1);

  char* payload = kelpie_bookmark_store_to_json(store);
  assert(payload != nullptr);
  const json entries = json::parse(payload);
  kelpie_free_string(payload);
  assert(entries.size() == 1);

  kelpie_bookmark_store_load_json(
      store, R"([{"id":"x","title":"Reloaded","url":"https://reload.test","created_at":"2026-04-01T12:00:00Z"}])");
  assert(kelpie_bookmark_store_count(store) == 1);

  kelpie_bookmark_store_destroy(store);
}

}  // namespace

int main() {
  try {
    TestEmptyStore();
    TestAddRemoveAndClear();
    TestLoadJsonRoundTripAndInvalidInput();
    TestCApiRoundTrip();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
