#include "mollotov/console_store.h"
#include "mollotov/state_c_api.h"

#include <cassert>
#include <iostream>

#include <nlohmann/json.hpp>

namespace {

using json = nlohmann::json;

void TestAppendFilteringAndErrorsOnly() {
  mollotov::ConsoleStore store;
  store.Append(mollotov::ConsoleEntry{
      "",
      mollotov::ConsoleLevel::kLog,
      "plain log",
      "app.js",
      4,
      2,
      "2026-04-01T12:00:00Z",
      std::nullopt,
  });
  store.Append(mollotov::ConsoleEntry{
      "",
      mollotov::ConsoleLevel::kError,
      "boom",
      "app.js",
      8,
      3,
      "2026-04-01T12:00:01Z",
      std::string("Error: boom"),
  });

  const json all_entries = json::parse(store.ToJson());
  assert(all_entries.size() == 2);

  const json errors = json::parse(store.GetErrorsOnly());
  assert(errors.size() == 1);
  assert(errors[0]["level"] == "error");
  assert(errors[0]["stack_trace"] == "Error: boom");
}

void TestCapacityAndLoadJson() {
  mollotov::ConsoleStore store;
  for (int index = 0; index < 1005; ++index) {
    store.Append(mollotov::ConsoleEntry{
        "",
        mollotov::ConsoleLevel::kDebug,
        "message-" + std::to_string(index),
        "",
        0,
        0,
        "2026-04-01T12:00:00Z",
        std::nullopt,
    });
  }
  assert(store.Count() == 1000);

  const json debug_entries = json::parse(store.ToJson(std::string("debug")));
  assert(debug_entries.size() == 1000);
  assert(debug_entries[0]["text"] == "message-5");

  store.LoadJson(R"([
    {"id":"1","level":"warn","text":"warn","source":"app.js","line":1,"column":2,"timestamp":"2026-04-01T12:00:00Z","stack_trace":null},
    {"id":"2","level":"error","text":"error","source":"app.js","line":3,"column":4,"timestamp":"2026-04-01T12:00:01Z","stack_trace":"trace"}
  ])");
  assert(store.Count() == 2);
  assert(json::parse(store.ToJson("warn")).size() == 1);

  store.LoadJson("oops");
  assert(store.Count() == 0);
}

void TestCApiOperations() {
  MollotovConsoleStoreRef store = mollotov_console_store_create();
  assert(store != nullptr);

  assert(mollotov_console_store_append_json(
             store,
             R"({"level":"error","text":"ffi-error","source":"ffi.js","line":1,"column":2,"timestamp":"2026-04-01T12:00:00Z","stack_trace":"trace"})") == 1);
  assert(mollotov_console_store_append_json(
             store,
             R"({"level":"info","text":"ffi-info","source":"ffi.js","line":3,"column":4,"timestamp":"2026-04-01T12:00:01Z"})") == 1);

  char* errors = mollotov_console_store_get_errors_only(store);
  assert(errors != nullptr);
  const json error_entries = json::parse(errors);
  mollotov_free_string(errors);
  assert(error_entries.size() == 1);
  assert(error_entries[0]["text"] == "ffi-error");

  mollotov_console_store_destroy(store);
}

}  // namespace

int main() {
  try {
    TestAppendFilteringAndErrorsOnly();
    TestCapacityAndLoadJson();
    TestCApiOperations();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
