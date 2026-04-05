#include "kelpie/desktop_app.h"

#include <memory>
#include <thread>

#include "kelpie/bookmark_store.h"
#include "kelpie/console_store.h"
#include "kelpie/desktop_http_server.h"
#include "kelpie/desktop_mdns.h"
#include "kelpie/desktop_mcp_server.h"
#include "kelpie/desktop_router.h"
#include "kelpie/history_store.h"
#include "kelpie/handler_context.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/network_traffic_store.h"
#include "kelpie/response_helpers.h"
#include "handlers/bookmark_handler.h"
#include "handlers/browser_mgmt_handler.h"
#include "handlers/console_handler.h"
#include "handlers/cookie_handler.h"
#include "handlers/device_handler.h"
#include "handlers/dom_handler.h"
#include "handlers/evaluate_handler.h"
#include "handlers/history_handler.h"
#include "handlers/interaction_handler.h"
#include "handlers/navigation_handler.h"
#include "handlers/network_handler.h"
#include "handlers/renderer_handler.h"
#include "handlers/screenshot_handler.h"
#include "handlers/scroll_handler.h"
#include "handlers/viewport_handler.h"

namespace kelpie {
namespace {

void AppendConsole(ConsoleStore& store, const nlohmann::json& event) {
  const auto level = ConsoleStore::LevelFromString(event.value("level", std::string("log")));
  if (!level.has_value()) {
    return;
  }
  store.Append(ConsoleEntry{
      event.value("id", std::string()),
      *level,
      event.value("text", std::string()),
      event.value("source", std::string()),
      event.value("line", 0),
      event.value("column", 0),
      event.value("timestamp", std::string()),
      event.contains("stack_trace") && !event["stack_trace"].is_null()
          ? std::optional<std::string>(event["stack_trace"].get<std::string>())
          : std::nullopt,
  });
}

void AppendNetwork(NetworkTrafficStore& store, const nlohmann::json& event) {
  store.Append(TrafficEntry{
      event.value("id", std::string()),
      event.value("method", std::string("GET")),
      event.value("url", std::string()),
      event.value("status", 0),
      event.value("contentType", std::string()),
      {},
      {},
      "",
      "",
      event.value("timestamp", std::string()),
      event.value("duration", 0),
      event.value("size", 0),
      event.value("initiator", std::string("browser")),
  });
}

std::vector<std::string> UnsupportedMethods() {
  return {
      "set-home",           "get-home",           "debug-screens",
      "set-debug-overlay",  "get-debug-overlay",  "tap",
      "find-element",       "find-button",        "find-link",
      "find-input",         "toast",              "get-accessibility-tree",
      "click-annotation",   "fill-annotation",    "get-visible-elements",
      "get-page-text",      "get-form-state",     "get-dialog",
      "handle-dialog",      "set-dialog-auto-handler",
      "get-iframes",        "switch-to-iframe",   "switch-to-main",
      "get-iframe-context", "watch-mutations",    "get-mutations",
      "stop-watching",      "query-shadow-dom",   "get-shadow-roots",
      "get-clipboard",      "set-clipboard",      "set-geolocation",
      "clear-geolocation",  "set-request-interception",
      "get-intercepted-requests", "clear-request-interception",
      "show-keyboard",      "hide-keyboard",      "get-keyboard-state",
      "is-element-obscured","set-orientation",    "get-orientation",
      "safari-auth",
  };
}

}  // namespace

class DesktopApp::Impl {
 public:
  Config config;
  bool running = false;

  BookmarkStore bookmark_store;
  HistoryStore history_store;
  ConsoleStore console_store;
  NetworkTrafficStore network_store;

  DesktopEngine engine;
  DesktopRouter router;
  DesktopHttpServer http_server;
  DesktopMcpServer mcp_server;
  McpRegistry mcp_registry;

  std::thread mcp_thread;
  std::unique_ptr<HandlerContext> handler_context;

  std::unique_ptr<NavigationHandler> navigation_handler;
  std::unique_ptr<InteractionHandler> interaction_handler;
  std::unique_ptr<DomHandler> dom_handler;
  std::unique_ptr<EvaluateHandler> evaluate_handler;
  std::unique_ptr<ScreenshotHandler> screenshot_handler;
  std::unique_ptr<ScrollHandler> scroll_handler;
  std::unique_ptr<ConsoleHandler> console_handler;
  std::unique_ptr<NetworkHandler> network_handler;
  std::unique_ptr<DeviceHandler> device_handler;
  std::unique_ptr<BookmarkHandler> bookmark_handler;
  std::unique_ptr<HistoryHandler> history_handler;
  std::unique_ptr<BrowserManagementHandler> browser_handler;
  std::unique_ptr<RendererHandler> renderer_handler;
  std::unique_ptr<ViewportHandler> viewport_handler;
  std::unique_ptr<CookieHandler> cookie_handler;

  DesktopHandlerRuntime BuildRuntime() {
    DesktopHandlerRuntime runtime;
    handler_context = std::make_unique<HandlerContext>(&engine.renderer());
    runtime.handler_context = handler_context.get();
    runtime.bookmark_store = &bookmark_store;
    runtime.history_store = &history_store;
    runtime.console_store = &console_store;
    runtime.network_store = &network_store;
    runtime.device_info_provider = config.device_info_provider;
    runtime.platform = config.platform;
    runtime.engine_name = config.engine_name;
    runtime.viewport_supplier = [this]() {
      const DesktopEngine::ViewportState viewport = engine.viewport();
      nlohmann::json response = {
          {"width", viewport.width},
          {"height", viewport.height},
          {"devicePixelRatio", viewport.device_pixel_ratio},
          {"platform", PlatformToString(config.platform)},
          {"deviceName", config.device_info_provider == nullptr
                             ? std::string("Kelpie Desktop")
                             : config.device_info_provider->GetDeviceInfo().value("name",
                                                                                  std::string("Kelpie Desktop"))},
          {"orientation", viewport.width >= viewport.height ? "landscape" : "portrait"},
      };
      return response;
    };
    runtime.capabilities_supplier = [this]() {
      const McpCapabilities capabilities =
          mcp_registry.get_capabilities(config.platform, config.engine_name);
      return SuccessResponse({
          {"platform", PlatformToString(config.platform)},
          {"engine", config.engine_name},
          {"supported", capabilities.supported},
          {"partial", capabilities.partial},
          {"unsupported", capabilities.unsupported},
      });
    };
    runtime.renderer_supplier = [this]() {
      return SuccessResponse({{"current", config.engine_name}, {"available", {"chromium"}}});
    };
    runtime.resize_viewport = [this](int width, int height) {
      return engine.ResizeViewport(width, height);
    };
    runtime.reset_viewport = [this]() {
      engine.ResizeViewport(config.engine.viewport.width, config.engine.viewport.height);
    };
    return runtime;
  }

  void RegisterHandlers() {
    const DesktopHandlerRuntime runtime = BuildRuntime();
    navigation_handler = std::make_unique<NavigationHandler>(runtime);
    interaction_handler = std::make_unique<InteractionHandler>(runtime);
    dom_handler = std::make_unique<DomHandler>(runtime);
    evaluate_handler = std::make_unique<EvaluateHandler>(runtime);
    screenshot_handler = std::make_unique<ScreenshotHandler>(runtime);
    scroll_handler = std::make_unique<ScrollHandler>(runtime);
    console_handler = std::make_unique<ConsoleHandler>(runtime);
    network_handler = std::make_unique<NetworkHandler>(runtime);
    device_handler = std::make_unique<DeviceHandler>(runtime);
    bookmark_handler = std::make_unique<BookmarkHandler>(runtime);
    history_handler = std::make_unique<HistoryHandler>(runtime);
    browser_handler = std::make_unique<BrowserManagementHandler>(runtime);
    renderer_handler = std::make_unique<RendererHandler>(runtime);
    viewport_handler = std::make_unique<ViewportHandler>(runtime);
    cookie_handler = std::make_unique<CookieHandler>(runtime);

    navigation_handler->Register(router);
    interaction_handler->Register(router);
    dom_handler->Register(router);
    evaluate_handler->Register(router);
    screenshot_handler->Register(router);
    scroll_handler->Register(router);
    console_handler->Register(router);
    network_handler->Register(router);
    device_handler->Register(router);
    bookmark_handler->Register(router);
    history_handler->Register(router);
    browser_handler->Register(router);
    renderer_handler->Register(router);
    viewport_handler->Register(router);
    cookie_handler->Register(router);

    for (const std::string& method : UnsupportedMethods()) {
      if (!router.Has(method)) {
        router.Register(method, [method](const nlohmann::json&) {
          return ErrorResponse(ErrorCode::kPlatformNotSupported,
                               method + " is not supported on desktop Chromium");
        });
      }
    }
  }

  StringMap BuildTxtRecord() const {
    StringMap txt = config.device_info_provider == nullptr ? StringMap{} : config.device_info_provider->GetMdnsMetadata();
    txt["platform"] = PlatformToString(config.platform);
    txt["engine"] = config.engine_name;
    txt["port"] = std::to_string(http_server.bound_port() > 0 ? http_server.bound_port() : config.port);
    txt["version"] = config.app_version;
    const DesktopEngine::ViewportState viewport = engine.viewport();
    txt["width"] = std::to_string(viewport.width);
    txt["height"] = std::to_string(viewport.height);
    return txt;
  }
};

DesktopApp::DesktopApp() : impl_(std::make_unique<Impl>()) {}

DesktopApp::~DesktopApp() {
  Stop();
}

bool DesktopApp::Start(const Config& config) {
  if (impl_->running) {
    return false;
  }

  impl_->config = config;
  impl_->engine.SetConsoleSink([this](const nlohmann::json& event) {
    AppendConsole(impl_->console_store, event);
  });
  impl_->engine.SetNetworkSink([this](const nlohmann::json& event) {
    AppendNetwork(impl_->network_store, event);
  });
  impl_->engine.SetNavigationSink([this](const std::string& url, const std::string& title) {
    impl_->history_store.Record(url, title);
    impl_->history_store.UpdateLatestTitle(url, title);
  });

  if (!impl_->engine.Initialize(config.engine)) {
    return false;
  }

  impl_->RegisterHandlers();

  impl_->http_server.SetRouter(&impl_->router);
  DesktopHttpServer::Config server_config;
  server_config.port = config.port;
  if (!impl_->http_server.Start(server_config)) {
    impl_->engine.Shutdown();
    return false;
  }

  impl_->mcp_server.SetRegistry(&impl_->mcp_registry);
  impl_->mcp_server.SetRouter(&impl_->router);
  if (config.start_stdio_mcp) {
    impl_->mcp_thread = std::thread([this, config]() {
      DesktopMcpServer::Config mcp_config;
      mcp_config.platform = config.platform;
      mcp_config.engine = config.engine_name;
      mcp_config.server_name = config.app_name;
      mcp_config.server_version = config.app_version;
      impl_->mcp_server.Run(mcp_config);
    });
  }

  if (config.mdns != nullptr) {
    config.mdns->Start(impl_->http_server.bound_port(), impl_->BuildTxtRecord());
  }

  impl_->running = true;
  return true;
}

void DesktopApp::Stop() {
  if (!impl_->running) {
    return;
  }
  if (impl_->config.mdns != nullptr) {
    impl_->config.mdns->Stop();
  }
  impl_->http_server.Stop();
  impl_->engine.Shutdown();
  if (impl_->mcp_thread.joinable()) {
    impl_->mcp_thread.detach();
  }
  impl_->running = false;
}

void DesktopApp::Tick() {
  impl_->engine.DoMessageLoopWork();
}

bool DesktopApp::is_running() const {
  return impl_->running;
}

DesktopEngine& DesktopApp::engine() {
  return impl_->engine;
}

DesktopRouter& DesktopApp::router() {
  return impl_->router;
}

DesktopHttpServer& DesktopApp::http_server() {
  return impl_->http_server;
}

DesktopMcpServer& DesktopApp::mcp_server() {
  return impl_->mcp_server;
}

McpRegistry& DesktopApp::mcp_registry() {
  return impl_->mcp_registry;
}

}  // namespace kelpie
