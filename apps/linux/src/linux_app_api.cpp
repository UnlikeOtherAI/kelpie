#include "linux_app_internal.h"

#include <set>

#include "kelpie/error_codes.h"
#include "kelpie/response_helpers.h"

namespace kelpie::linuxapp {

LinuxApp::json LinuxApp::ConsoleMessages(const std::optional<std::string>& level) const {
  const json messages = json::parse(impl_->console.ToJson(level));
  return {{"success", true}, {"messages", messages}, {"count", messages.size()}, {"hasMore", false}};
}

LinuxApp::json LinuxApp::NetworkEntries(const std::optional<std::string>& method,
                                        const std::optional<std::string>& type,
                                        const std::optional<std::string>& source) const {
  const json raw = json::parse(impl_->network.ToJson());
  json filtered = json::array();
  for (const auto& entry : raw) {
    if (method.has_value() && entry.value("method", "") != *method) {
      continue;
    }
    if (type.has_value() && CategoryForFilter(entry) != *type) {
      continue;
    }
    if (source.has_value() && entry.value("initiator", "browser") != *source) {
      continue;
    }
    filtered.push_back({
        {"url", entry.value("url", "")},
        {"type", CategoryForFilter(entry)},
        {"method", entry.value("method", "")},
        {"status", entry.value("status_code", 0)},
        {"statusText", nullptr},
        {"mimeType", entry.value("content_type", "")},
        {"size", entry.value("size", 0)},
        {"transferSize", entry.value("size", 0)},
        {"timing", {{"started", entry.value("start_time", "")}, {"total", entry.value("duration", 0)}}},
        {"initiator", entry.value("initiator", "browser")},
    });
  }
  return {{"success", true}, {"entries", filtered}, {"count", filtered.size()}, {"hasMore", false}};
}

LinuxApp::json LinuxApp::DeviceInfo() const {
  const DeviceInfoSnapshot snapshot = impl_->device_info.Collect();
  const auto uptime = std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::steady_clock::now() - impl_->started_at);
  json payload = impl_->device_info.ToJson(snapshot,
                                           impl_->bound_port,
                                           impl_->config.width,
                                           impl_->config.height,
                                           MdnsActive(),
                                           impl_->http_server.running(),
                                           impl_->mdns.ServiceName(),
                                           impl_->version,
                                           uptime.count());
  payload["success"] = true;
  return payload;
}

LinuxApp::json LinuxApp::Capabilities() const {
  const std::set<std::string> supported_routes = {
      "navigate",         "back",            "forward",          "reload",
      "get-current-url",  "set-home",        "get-home",         "evaluate",
      "get-device-info",  "get-capabilities","get-bookmarks",    "add-bookmark",
      "remove-bookmark",  "clear-bookmarks", "get-history",      "clear-history",
      "get-network-log",  "get-console-messages", "get-js-errors","toast",
      "set-fullscreen",   "get-fullscreen",
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
    if (tool.http_endpoint == "screenshot" && !ScreenshotSupported()) {
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

LinuxApp::json LinuxApp::HandleApiRequest(std::string_view endpoint,
                                          const json& params,
                                          int* status_code) {
  if (status_code != nullptr) {
    *status_code = 200;
  }

  try {
    if (endpoint == "navigate") {
      const std::string url = params.value("url", "");
      if (url.empty()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams, "url is required");
      }
      Navigate(url);
      return kelpie::SuccessResponse({{"url", CurrentUrl()}, {"title", CurrentTitle()}, {"loadTime", 0}});
    }
    if (endpoint == "back") {
      GoBack();
      return kelpie::SuccessResponse({{"url", CurrentUrl()}, {"title", CurrentTitle()}});
    }
    if (endpoint == "forward") {
      GoForward();
      return kelpie::SuccessResponse({{"url", CurrentUrl()}, {"title", CurrentTitle()}});
    }
    if (endpoint == "reload") {
      Reload();
      return kelpie::SuccessResponse({{"url", CurrentUrl()}, {"loadTime", 0}});
    }
    if (endpoint == "get-current-url") {
      return kelpie::SuccessResponse({{"url", CurrentUrl()}, {"title", CurrentTitle()}});
    }
    if (endpoint == "set-home") {
      const std::string url = params.value("url", "");
      if (url.empty()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams, "url is required");
      }
      SetHomeUrl(url);
      return kelpie::SuccessResponse({{"url", HomeUrl()}});
    }
    if (endpoint == "get-home") {
      return kelpie::SuccessResponse({{"url", HomeUrl()}});
    }
    if (endpoint == "evaluate") {
      return kelpie::SuccessResponse(
          {{"result", impl_->handler_context.EvaluateJsReturningString(params.value("expression", ""))}});
    }
    if (endpoint == "screenshot") {
      if (status_code != nullptr) {
        *status_code = 503;
      }
      return kelpie::ErrorResponse("cef_unavailable", "CEF SDK is not linked in this build");
    }
    if (endpoint == "get-device-info") {
      return DeviceInfo();
    }
    if (endpoint == "get-capabilities") {
      return Capabilities();
    }
    if (endpoint == "get-bookmarks") {
      const json bookmarks = json::parse(BookmarksJson());
      return kelpie::SuccessResponse({{"bookmarks", bookmarks}, {"count", bookmarks.size()}});
    }
    if (endpoint == "add-bookmark") {
      const std::string url = params.value("url", CurrentUrl());
      const std::string title = params.value("title", CurrentTitle());
      AddBookmark(title, url);
      return kelpie::SuccessResponse({{"url", url}, {"title", title}});
    }
    if (endpoint == "remove-bookmark") {
      RemoveBookmark(params.value("id", ""));
      return kelpie::SuccessResponse();
    }
    if (endpoint == "clear-bookmarks") {
      ClearBookmarks();
      return kelpie::SuccessResponse();
    }
    if (endpoint == "get-history") {
      const json history = json::parse(HistoryJson());
      return kelpie::SuccessResponse({{"entries", history}, {"count", history.size()}});
    }
    if (endpoint == "clear-history") {
      ClearHistory();
      return kelpie::SuccessResponse();
    }
    if (endpoint == "get-console-messages") {
      return ConsoleMessages(params.contains("level") && !params["level"].is_null()
                                 ? std::optional<std::string>(params["level"].get<std::string>())
                                 : std::nullopt);
    }
    if (endpoint == "get-js-errors") {
      const json messages = ConsoleMessages("error");
      return kelpie::SuccessResponse({{"errors", messages["messages"]}, {"count", messages["count"]}});
    }
    if (endpoint == "get-network-log") {
      return NetworkEntries(
          params.contains("method") && !params["method"].is_null()
              ? std::optional<std::string>(params["method"].get<std::string>())
              : std::nullopt,
          params.contains("type") && !params["type"].is_null()
              ? std::optional<std::string>(params["type"].get<std::string>())
              : std::nullopt,
          params.contains("source") && !params["source"].is_null()
              ? std::optional<std::string>(params["source"].get<std::string>())
              : std::nullopt);
    }
    if (endpoint == "toast") {
      ShowToast(params.value("message", ""));
      return kelpie::SuccessResponse();
    }
    if (endpoint == "set-fullscreen") {
      SetFullscreen(params.value("enabled", true));
      return kelpie::SuccessResponse({{"enabled", WantsFullscreen()}});
    }
    if (endpoint == "get-fullscreen") {
      return kelpie::SuccessResponse({{"enabled", IsFullscreen()}});
    }

    if (status_code != nullptr) {
      *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPlatformNotSupported);
    }
    return kelpie::ErrorResponse(kelpie::ErrorCode::kPlatformNotSupported,
                                   "Method is not implemented on Linux yet");
  } catch (const std::exception& exception) {
    if (status_code != nullptr) {
      *status_code = 500;
    }
    return kelpie::ErrorResponse("INTERNAL_ERROR", exception.what());
  }
}

}  // namespace kelpie::linuxapp
