#include <cassert>
#include <cstdlib>
#undef assert
#define assert(expression) do { if (!(expression)) std::abort(); } while (false)

#include "desktop_devtools.h"

int main() {
  using Json = nlohmann::json;
  kelpie::DesktopNetworkEventAdapter events;

  assert(!events.Observe("Network.responseReceived", Json::object()));
  assert(!events.Observe("Network.loadingFinished", {{"requestId", "missing"}}));
  assert(!events.Observe("Network.requestWillBeSent", {
      {"requestId", "ping"}, {"timestamp", 10.0}, {"wallTime", 1704067200.25}, {"type", "Fetch"},
      {"initiator", {{"type", "script"}}},
      {"request", {{"url", "http://127.0.0.1/api/ping"}, {"method", "GET"}}},
  }));
  assert(!events.Observe("Network.responseReceived", {
      {"requestId", "ping"}, {"type", "Fetch"},
      {"response", {{"status", 204}, {"mimeType", "application/json"}}},
  }));
  const auto complete = events.Observe("Network.loadingFinished", {
      {"requestId", "ping"}, {"timestamp", 10.125}, {"encodedDataLength", 44},
  });
  assert(complete.has_value());
  assert((*complete)["url"] == "http://127.0.0.1/api/ping");
  assert((*complete)["method"] == "GET");
  assert((*complete)["status"] == 204);
  assert((*complete)["contentType"] == "application/json");
  assert((*complete)["size"] == 44);
  assert((*complete)["duration"] == 125);
  assert((*complete)["initiator"] == "js");
  assert((*complete)["timestamp"] == "2024-01-01T00:00:00.250Z");
  assert(!events.Observe("Network.loadingFinished", {{"requestId", "ping"}}));

  assert(!events.Observe("Network.requestWillBeSent", {
      {"requestId", "failed"}, {"timestamp", 20.0}, {"wallTime", 1704067201.0},
      {"request", {{"url", "http://127.0.0.1/api/fail"}, {"method", "POST"}}},
  }));
  const auto failed = events.Observe("Network.loadingFailed", {
      {"requestId", "failed"}, {"timestamp", 20.25}, {"errorText", "net::ERR_FAILED"},
  });
  assert(failed.has_value());
  assert((*failed)["status"] == 0);
  assert((*failed)["failure"] == "net::ERR_FAILED");
  assert((*failed)["duration"] == 250);
  assert((*failed)["timestamp"] == "2024-01-01T00:00:01.000Z");

  for (int index = 0; index < 513; ++index) {
    assert(!events.Observe("Network.requestWillBeSent", {
        {"requestId", "bounded-" + std::to_string(index)},
        {"request", {{"url", "http://127.0.0.1/resource"}, {"method", "GET"}}},
    }));
  }
  assert(events.pending_count() <= 512);
  events.Clear();
  assert(events.pending_count() == 0);
  return 0;
}
