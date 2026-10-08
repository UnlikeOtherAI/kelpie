#include "linux_app_internal.h"
#include "tap_runtime_utils.h"
#include "web_runtime_utils.h"

#include <algorithm>
#include <cmath>
#include <optional>
#include <set>

#include "kelpie/error_codes.h"
#include "kelpie/base64.h"
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
                                           std::string(),
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
    if (endpoint == "report-issue") {
      return ReportIssue(params);
    }
    if (endpoint == "get-tap-calibration") {
      const TapCalibration calibration = LoadTapCalibration(impl_->config.profile_dir);
      return kelpie::SuccessResponse(
          {{"offsetX", calibration.offset_x}, {"offsetY", calibration.offset_y}});
    }
    if (endpoint == "set-tap-calibration") {
      const auto offset_x = JsonNumber(params, "offsetX");
      const auto offset_y = JsonNumber(params, "offsetY");
      if (!offset_x.has_value() || !offset_y.has_value() ||
          !std::isfinite(*offset_x) || !std::isfinite(*offset_y)) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams,
                                     "offsetX and offsetY are required numbers");
      }
      const TapCalibration calibration =
          SaveTapCalibration(impl_->config.profile_dir, *offset_x, *offset_y);
      return kelpie::SuccessResponse(
          {{"offsetX", calibration.offset_x}, {"offsetY", calibration.offset_y}});
    }
    if (endpoint == "evaluate") {
      return kelpie::SuccessResponse(
          {{"result", impl_->handler_context.EvaluateJsReturningString(params.value("expression", ""))}});
    }
    if (endpoint == "click") {
      const auto selector_it = params.find("selector");
      if (selector_it == params.end() || !selector_it->is_string() ||
          selector_it->get<std::string>().empty()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams, "selector is required");
      }
      if (!HasNativeBrowser()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPlatformNotSupported);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kPlatformNotSupported,
                                     "click requires a browser-backed Linux renderer");
      }
      const json result = impl_->handler_context.EvaluateJsReturningJson(
          SelectorActivationScript(selector_it->get<std::string>()));
      if (result.value("error", std::string()) == "not_found") {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kElementNotFound);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kElementNotFound,
                                     "No element matching selector",
                                     result.value("diagnostics", json::object()));
      }
      if (result.value("error", std::string()) == "not_visible") {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kElementNotVisible);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kElementNotVisible,
                                     "Element is not visible or is obscured",
                                     result.value("diagnostics", json::object()));
      }
      return kelpie::SuccessResponse({{"element", result}});
    }
    if (endpoint == "tap") {
      const auto requested_x = JsonNumber(params, "x");
      const auto requested_y = JsonNumber(params, "y");
      if (!requested_x.has_value() || !requested_y.has_value() ||
          !std::isfinite(*requested_x) || !std::isfinite(*requested_y)) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams,
                                     "x and y are required numbers");
      }
      if (!HasNativeBrowser()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPlatformNotSupported);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kPlatformNotSupported,
                                     "tap requires a browser-backed Linux renderer");
      }

      const TapCalibration calibration = LoadTapCalibration(impl_->config.profile_dir);
      const json viewport = impl_->handler_context.EvaluateJsReturningJson(
          "(() => ({width: Math.max(window.innerWidth || 0, 1), height: Math.max(window.innerHeight || 0, 1)}))()");
      const double width = viewport.value("width", 1.0);
      const double height = viewport.value("height", 1.0);
      const double applied_x =
          ClampCoordinate(*requested_x + calibration.offset_x, 0.0, std::max(width - 1.0, 0.0));
      const double applied_y =
          ClampCoordinate(*requested_y + calibration.offset_y, 0.0, std::max(height - 1.0, 0.0));
      const std::string color_rgb =
          OverlayRgbFromHex(params.value("color", std::string("#3B82F6")));
      const json diagnostics = impl_->handler_context.EvaluateJsReturningJson(
          TapScript(*requested_x,
                    *requested_y,
                    applied_x,
                    applied_y,
                    calibration.offset_x,
                    calibration.offset_y,
                    color_rgb));
      return kelpie::SuccessResponse({{"x", *requested_x},
                                      {"y", *requested_y},
                                      {"appliedX", applied_x},
                                      {"appliedY", applied_y},
                                      {"offsetX", calibration.offset_x},
                                      {"offsetY", calibration.offset_y},
                                      {"diagnostics", diagnostics}});
    }
    if (endpoint == "screenshot") {
      const auto resolution = ParseScreenshotResolution(params);
      if (!resolution.has_value()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams,
                                     "resolution must be 'native' or 'viewport'");
      }
      if (!ScreenshotSupported()) {
        if (status_code != nullptr) {
          *status_code = 503;
        }
        return kelpie::ErrorResponse("cef_unavailable", "CEF SDK is not linked in this build");
      }
      const ScreenshotViewportMetrics viewport =
          LoadScreenshotViewportMetrics(impl_->handler_context);
      const std::vector<std::uint8_t> bytes =
          ScaleScreenshotBytes(SnapshotBytes(), *resolution, viewport);
      const auto dimensions = ParsePngDimensions(bytes);
      if (bytes.empty() || !dimensions.has_value()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kWebviewError);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kWebviewError,
                                     "Failed to capture screenshot");
      }
      json payload = ScreenshotMetadata(dimensions->first, dimensions->second, "png",
                                        *resolution, viewport);
      payload["image"] = kelpie::Base64Encode(bytes);
      return kelpie::SuccessResponse(payload);
    }
    if (endpoint == "screenshot-annotated") {
      const auto resolution = ParseScreenshotResolution(params);
      if (!resolution.has_value()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams,
                                     "resolution must be 'native' or 'viewport'");
      }
      if (!ScreenshotSupported()) {
        if (status_code != nullptr) {
          *status_code = 503;
        }
        return kelpie::ErrorResponse("cef_unavailable", "CEF SDK is not linked in this build");
      }
      const ScreenshotViewportMetrics viewport =
          LoadScreenshotViewportMetrics(impl_->handler_context);
      const std::vector<std::uint8_t> bytes =
          ScaleScreenshotBytes(SnapshotBytes(), *resolution, viewport);
      const auto dimensions = ParsePngDimensions(bytes);
      if (bytes.empty() || !dimensions.has_value()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kWebviewError);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kWebviewError,
                                     "Failed to capture screenshot");
      }
      json payload = ScreenshotMetadata(dimensions->first, dimensions->second, "png",
                                        *resolution, viewport);
      payload["image"] = kelpie::Base64Encode(bytes);
      payload["annotations"] = impl_->handler_context.EvaluateJsReturningJson(AnnotationElementsScript());
      return kelpie::SuccessResponse(payload);
    }
    if (endpoint == "click-annotation") {
      const auto index = params.find("index");
      if (index == params.end() || !index->is_number_integer()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams, "index is required");
      }
      if (!HasNativeBrowser()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPlatformNotSupported);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kPlatformNotSupported,
                                     "click-annotation requires a browser-backed Linux renderer");
      }
      const json result =
          impl_->handler_context.EvaluateJsReturningJson(AnnotationActivationScript(index->get<int>()));
      if (result.value("error", std::string()) == "not_found") {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kElementNotFound);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kElementNotFound,
                                     "Annotation index not found",
                                     result.value("diagnostics", json::object()));
      }
      if (result.value("error", std::string()) == "not_visible") {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kElementNotVisible);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kElementNotVisible,
                                     "Annotated element is not visible or is obscured",
                                     result.value("diagnostics", json::object()));
      }
      return kelpie::SuccessResponse({{"element", result}});
    }
    if (endpoint == "fill-annotation") {
      const auto index = params.find("index");
      const auto value = params.find("value");
      if (index == params.end() || !index->is_number_integer() || value == params.end() ||
          !value->is_string()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams,
                                     "index and value are required");
      }
      if (!HasNativeBrowser()) {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kPlatformNotSupported);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kPlatformNotSupported,
                                     "fill-annotation requires a browser-backed Linux renderer");
      }
      const json result = impl_->handler_context.EvaluateJsReturningJson(
          FillAnnotationScript(index->get<int>(), value->get<std::string>()));
      if (result.value("error", std::string()) == "not_found") {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kElementNotFound);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kElementNotFound,
                                     "Annotation index not found",
                                     result.value("diagnostics", json::object()));
      }
      if (result.value("error", std::string()) == "not_editable") {
        if (status_code != nullptr) {
          *status_code = kelpie::ErrorCodeHttpStatus(kelpie::ErrorCode::kInvalidParams);
        }
        return kelpie::ErrorResponse(kelpie::ErrorCode::kInvalidParams,
                                     "Annotated element is not an editable form control",
                                     result.value("diagnostics", json::object()));
      }
      return kelpie::SuccessResponse({{"element", result}, {"value", value->get<std::string>()}});
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
