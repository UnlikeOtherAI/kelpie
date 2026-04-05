#include "kelpie/desktop_router.h"

#include <cassert>

int main() {
  kelpie::DesktopRouter router;
  router.Register("ping", [](const nlohmann::json& params) {
    return nlohmann::json{{"success", true}, {"echo", params.value("value", 0)}};
  });

  const auto ok = router.Dispatch("ping", {{"value", 7}});
  assert(ok.status_code == 200);
  assert(ok.body["success"] == true);
  assert(ok.body["echo"] == 7);

  const auto missing = router.Dispatch("missing", nlohmann::json::object());
  assert(missing.status_code == 404);
  assert(missing.body["success"] == false);
  assert(missing.body["error"]["code"] == "NOT_FOUND");

  return 0;
}
