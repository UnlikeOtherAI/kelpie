#include "kelpie/cef_renderer.h"

#include <cassert>

#include "kelpie/desktop_router.h"
#include "kelpie/handler_context.h"
#include "handlers/bookmark_handler.h"
#include "handlers/history_handler.h"
#include "handlers/renderer_handler.h"
#include "handlers/viewport_handler.h"

namespace {

class StubDeviceInfoProvider final : public kelpie::DeviceInfoProvider {
 public:
  nlohmann::json GetDeviceInfo() const override { return {{"name", "Stub Desktop"}}; }
  kelpie::StringMap GetMdnsMetadata() const override { return {{"name", "Stub Desktop"}}; }
};

}  // namespace

int main() {
  kelpie::CefRenderer renderer;
  kelpie::HandlerContext context(&renderer);
  kelpie::BookmarkStore bookmarks;
  kelpie::HistoryStore history;
  StubDeviceInfoProvider device_info;

  int width = 1280;
  int height = 720;

  kelpie::DesktopHandlerRuntime runtime;
  runtime.handler_context = &context;
  runtime.bookmark_store = &bookmarks;
  runtime.history_store = &history;
  runtime.device_info_provider = &device_info;
  runtime.renderer_supplier = []() {
    return kelpie::SuccessResponse({{"current", "chromium"}, {"available", {"chromium"}}});
  };
  runtime.viewport_supplier = [&]() {
    return nlohmann::json{{"width", width}, {"height", height}, {"devicePixelRatio", 1.0}};
  };
  runtime.resize_viewport = [&](int next_width, int next_height) {
    width = next_width;
    height = next_height;
    return true;
  };
  runtime.reset_viewport = [&]() {
    width = 1280;
    height = 720;
  };

  kelpie::DesktopRouter router;
  kelpie::BookmarkHandler bookmark_handler(runtime);
  kelpie::HistoryHandler history_handler(runtime);
  kelpie::RendererHandler renderer_handler(runtime);
  kelpie::ViewportHandler viewport_handler(runtime);
  bookmark_handler.Register(router);
  history_handler.Register(router);
  renderer_handler.Register(router);
  viewport_handler.Register(router);

  auto add = router.Dispatch("bookmarks-add", {{"url", "https://example.com"}, {"title", "Example"}});
  assert(add.status_code == 200);
  assert(add.body["bookmarks"].size() == 1);

  auto alias_list = router.Dispatch("get-bookmarks", nlohmann::json::object());
  assert(alias_list.body["bookmarks"].size() == 1);

  history.Record("https://example.com", "Example");
  auto history_list = router.Dispatch("get-history", {{"limit", 10}});
  assert(history_list.body["entries"].size() == 1);

  auto renderer_info = router.Dispatch("get-renderer", nlohmann::json::object());
  assert(renderer_info.body["success"] == true);
  assert(renderer_info.body["current"] == "chromium");

  auto resize = router.Dispatch("resize-viewport", {{"width", 390}, {"height", 844}});
  assert(resize.body["success"] == true);
  assert(resize.body["viewport"]["width"] == 390);
  assert(resize.body["viewport"]["height"] == 844);

  auto reset = router.Dispatch("reset-viewport", nlohmann::json::object());
  assert(reset.body["viewport"]["width"] == 1280);
  assert(reset.body["viewport"]["height"] == 720);

  return 0;
}
