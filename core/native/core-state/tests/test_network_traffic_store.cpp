#include "kelpie/network_traffic_store.h"
#include "kelpie/state_c_api.h"

#include <cassert>
#include <iostream>

#include <nlohmann/json.hpp>

namespace {

using json = nlohmann::json;

void TestAppendAndFiltering() {
  kelpie::NetworkTrafficStore store;
  store.Append(kelpie::TrafficEntry{
      "",
      "post",
      "https://api.test/data",
      201,
      "application/json",
      {{"accept", "application/json"}},
      {{"content-type", "application/json"}},
      "{\"ok\":true}",
      "{\"saved\":true}",
      "2026-04-01T12:00:00Z",
      23,
      120,
  });
  store.AppendDocumentNavigation("https://site.test", 200, "text/html", {{"server", "unit"}}, 512,
                                 "2026-04-01T12:00:10Z", 40);

  const json all_entries = json::parse(store.ToJson());
  assert(all_entries.size() == 2);
  assert(all_entries[0]["method"] == "POST");
  assert(all_entries[0]["category"] == "JSON");
  assert(all_entries[1]["category"] == "HTML");

  const json summary =
      json::parse(store.ToSummaryJson(std::string("post"), std::string("json"), std::string("200-299"),
                                      std::string("api.test")));
  assert(summary.size() == 1);
  assert(summary[0]["url"] == "https://api.test/data");
}

void TestSelectionAndTrimSafety() {
  kelpie::NetworkTrafficStore store;
  for (int index = 0; index < 3; ++index) {
    store.Append(kelpie::TrafficEntry{
        "",
        "GET",
        "https://trim.test/" + std::to_string(index),
        200,
        "text/plain",
        {},
        {},
        "",
        "",
        "2026-04-01T12:00:00Z",
        index,
        index,
    });
  }

  assert(store.Select(1));
  assert(store.SelectedIndex().has_value());
  assert(*store.SelectedIndex() == 1);

  for (int index = 3; index < 2002; ++index) {
    store.Append(kelpie::TrafficEntry{
        "",
        "GET",
        "https://trim.test/" + std::to_string(index),
        200,
        "text/plain",
        {},
        {},
        "",
        "",
        "2026-04-01T12:00:00Z",
        index,
        index,
    });
  }

  assert(store.Count() == 2000);
  assert(!store.SelectedIndex().has_value());
  assert(store.GetSelectedJson().empty());
}

void TestLoadJsonAndInvalidInput() {
  kelpie::NetworkTrafficStore store;
  store.LoadJson(R"([
    {
      "id":"a",
      "method":"GET",
      "url":"https://one.test",
      "status_code":200,
      "content_type":"text/css",
      "request_headers":{"accept":"text/css"},
      "response_headers":{"content-type":"text/css"},
      "request_body":"",
      "response_body":"",
      "start_time":"2026-04-01T12:00:00Z",
      "duration":10,
      "size":20
    }
  ])");

  const json entries = json::parse(store.ToJson());
  assert(entries.size() == 1);
  assert(entries[0]["category"] == "CSS");

  store.LoadJson("invalid");
  assert(store.Count() == 0);
}

void TestCApiOperations() {
  KelpieNetworkTrafficStoreRef store = kelpie_network_traffic_store_create();
  assert(store != nullptr);

  assert(kelpie_network_traffic_store_append_json(
             store,
             R"({"method":"post","url":"https://ffi.test/api","status_code":201,"content_type":"application/json"})") == 1);
  kelpie_network_traffic_store_append_document_navigation(
      store, "https://ffi.test/page", 200, "text/html", R"({"server":"ffi"})", 42,
      "2026-04-01T12:00:00Z", 9);

  char* summary =
      kelpie_network_traffic_store_to_summary_json(store, "POST", "json", "200-299", "ffi.test");
  assert(summary != nullptr);
  const json summary_entries = json::parse(summary);
  kelpie_free_string(summary);
  assert(summary_entries.size() == 1);

  assert(kelpie_network_traffic_store_select(store, 1) == 1);
  char* selected = kelpie_network_traffic_store_get_selected_json(store);
  assert(selected != nullptr);
  const json selected_entry = json::parse(selected);
  kelpie_free_string(selected);
  assert(selected_entry["category"] == "HTML");

  kelpie_network_traffic_store_destroy(store);
}

}  // namespace

int main() {
  try {
    TestAppendAndFiltering();
    TestSelectionAndTrimSafety();
    TestLoadJsonAndInvalidInput();
    TestCApiOperations();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
