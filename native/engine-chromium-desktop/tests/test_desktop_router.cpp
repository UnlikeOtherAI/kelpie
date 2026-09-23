#include "kelpie/desktop_router.h"

#include <cassert>
#include <string>

#include "kelpie/error_codes.h"
#include "kelpie/response_helpers.h"

int main() {
  kelpie::DesktopRouter router;
  router.Register("ping", [](const nlohmann::json& params) {
    return nlohmann::json{{"success", true}, {"echo", params.value("value", 0)}};
  });

  const auto ok = router.Dispatch("ping", {{"value", 7}});
  assert(ok.status_code == 200);
  assert(ok.body["success"] == true);
  assert(ok.body["echo"] == 7);
  assert(router.IsCallable("ping"));

  const auto missing = router.Dispatch("missing", nlohmann::json::object());
  assert(missing.status_code == 404);
  assert(missing.body["success"] == false);
  assert(missing.body["error"]["code"] == "NOT_FOUND");

  // A minimised window conflicts with the request's need for a current image.
  router.Register("minimised", [](const nlohmann::json&) {
    return kelpie::ErrorResponse("WINDOW_MINIMIZED", "The browser window is minimised");
  });
  const auto minimised = router.Dispatch("minimised", nlohmann::json::object());
  assert(minimised.status_code == 409);
  assert(kelpie::ErrorCodeFromString("WINDOW_MINIMIZED") == kelpie::ErrorCode::kWindowMinimized);
  assert(std::string(kelpie::ErrorCodeToString(kelpie::ErrorCode::kWindowMinimized)) == "WINDOW_MINIMIZED");

  router.Register("unsupported", [](const nlohmann::json&) {
    return nlohmann::json{{"success", false}};
  }, false);
  assert(router.Has("unsupported"));
  assert(!router.IsCallable("unsupported"));

  return 0;
}
