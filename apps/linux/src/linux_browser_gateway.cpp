#include "linux_app_internal.h"
#include "kelpie/native_extension_schema.h"
#include <set>

namespace kelpie::linuxapp {
LinuxApp::json LinuxApp::Capabilities() const {
  const std::set<std::string> supported_routes = {
      "navigate",         "back",            "forward",          "reload",
      "get-current-url",  "set-home",        "get-home",         "evaluate",
      "get-device-info",  "get-capabilities","bookmarks-list",    "bookmarks-add",
      "bookmarks-remove",  "bookmarks-clear", "history-list",      "history-clear",
      "get-network-log",  "get-console-messages", "get-js-errors","toast",
      "report-issue",
      "set-fullscreen",   "get-fullscreen",  "tap",              "click",
      "screenshot",       "screenshot-annotated", "click-annotation",
      "fill-annotation",
      "get-tap-calibration", "set-tap-calibration",
  };
  const std::set<std::string> partial_routes = {"evaluate", "get-console-messages", "get-network-log"};

  json supported = json::array();
  json partial = json::array();
  json unsupported = json::array();

  for (const auto& tool : impl_->registry.tools_for_platform(kelpie::Platform::kLinux)) {
    if (!kelpie::SupportsEngine(tool.availability, "chromium")) {
      continue;
    }
    if (impl_->config.headless && tool.availability.requires_ui) {
      unsupported.push_back(tool.http_endpoint);
      continue;
    }
    if (!tool.availability.allowed_headless && impl_->config.headless) {
      unsupported.push_back(tool.http_endpoint);
      continue;
    }
    if ((tool.http_endpoint == "screenshot" || tool.http_endpoint == "screenshot-annotated") &&
        !ScreenshotSupported()) {
      unsupported.push_back(tool.http_endpoint);
      continue;
    }
    if ((tool.http_endpoint == "click" || tool.http_endpoint == "click-annotation" ||
         tool.http_endpoint == "fill-annotation") &&
        !HasNativeBrowser()) {
      unsupported.push_back(tool.http_endpoint);
      continue;
    }
    if (supported_routes.count(tool.http_endpoint) == 0) {
      unsupported.push_back(tool.http_endpoint);
      continue;
    }
    if (partial_routes.count(tool.http_endpoint) != 0) {
      partial.push_back(tool.http_endpoint);
    } else {
      supported.push_back(tool.http_endpoint);
    }
  }

  return {{"success", true},
          {"version", impl_->version},
          {"platform", "linux"},
          {"supported", supported},
          {"partial", partial},
          {"unsupported", unsupported}};
}

LinuxApp::json LinuxApp::HandleBrowserGateway(const json& request, bool mcp) {
  if (!impl_->browser_gateway) {
    // The no-CEF fallback has product metadata/history controls, but no live DOM browser.
    const auto capabilities = Capabilities();
    std::set<std::string> methods;
    for (const auto& group : {"supported", "partial"}) for (const auto& method : capabilities[group]) methods.insert(method.get<std::string>());
    json extensions = json::array();
    for (const auto& tool : impl_->registry.tools_for_platform(Platform::kLinux)) {
      if (!methods.count(tool.http_endpoint)) continue;
      extensions.push_back({{"name", tool.name}, {"method", tool.http_endpoint}, {"description", tool.description},
        {"inputSchema", NativeExtensionInputSchema(tool.http_endpoint)}, {"mutates", NativeExtensionMutates(tool.http_endpoint)}});
    }
    impl_->browser_gateway = std::make_unique<BrowserGateway>(json{{"nativeMethods", methods}, {"browserAvailable", false},
      {"requireAuthorization", false}, {"extensions", extensions}});
  }
  auto step = mcp ? impl_->browser_gateway->BeginMcp(request) : impl_->browser_gateway->Begin(request);
  while (step.value("kind", std::string()) != "complete") {
    try {
      if (step["kind"] == "authorize") step = impl_->browser_gateway->Advance({{"success", true}});
      else {
        impl_->gateway_dispatch = true;
        int status = 200;
        const auto result = HandleApiRequest(step.at("method").get<std::string>(), step.at("params"), &status);
        impl_->gateway_dispatch = false;
        step = impl_->browser_gateway->Advance(result);
      }
    } catch (...) { impl_->gateway_dispatch = false; step = impl_->browser_gateway->Cancel(); }
  }
  return step.at("response");
}
}  // namespace kelpie::linuxapp
