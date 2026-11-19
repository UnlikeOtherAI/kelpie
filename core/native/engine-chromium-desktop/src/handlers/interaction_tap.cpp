#include "interaction_handler.h"

#include <cmath>
#include <fstream>

#include "tap_marker_resource.h"

namespace kelpie {
namespace {

using nlohmann::json;

bool FiniteNumber(const json& object, const char* key) {
  const auto value = object.find(key);
  return value != object.end() && value->is_number() && std::isfinite(value->get<double>());
}

bool ValidMarker(const json& marker) {
  if (!marker.is_object()) return false;
  for (auto field = marker.begin(); field != marker.end(); ++field) {
    if (field.key() == "style") {
      if (*field != "circle" && *field != "crosshair-coordinates") return false;
    } else if (field.key() == "durationMs") {
      if (!field->is_number()) return false;
      const double duration = field->get<double>();
      if (duration < 0 || duration > 2147483647.0 || duration != std::floor(duration)) return false;
    } else {
      return false;
    }
  }
  return true;
}

std::string MarkerRgb(const json& params) {
  const auto color = params.find("color");
  if (color == params.end() || !color->is_string()) return "59,130,246";
  std::string hex = color->get<std::string>();
  if (!hex.empty() && hex.front() == '#') hex.erase(0, 1);
  if (hex.size() != 6 || hex.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos) {
    return "59,130,246";
  }
  const auto rgb = std::stoul(hex, nullptr, 16);
  return std::to_string(rgb >> 16) + "," + std::to_string((rgb >> 8) & 255) + "," +
         std::to_string(rgb & 255);
}

json TapOffsets(const std::filesystem::path& path) {
  json result = {{"offsetX", 0.0}, {"offsetY", 0.0}};
  if (path.empty()) return result;
  std::ifstream file(path);
  if (!file) return result;
  const auto saved = json::parse(file, nullptr, false);
  for (const char* key : {"offsetX", "offsetY"}) {
    if (FiniteNumber(saved, key)) result[key] = saved[key];
  }
  return result;
}

std::string TapMarkerExpression(const json& params, const json& marker, const json& offsets,
                                std::string coordinate_space) {
  std::transform(coordinate_space.begin(), coordinate_space.end(), coordinate_space.begin(),
                 [](unsigned char character) { return std::tolower(character); });
  const auto arguments = json::array({params["x"], params["y"], offsets["offsetX"], offsets["offsetY"],
                                     coordinate_space == "screenshot", MarkerRgb(params),
                                     marker.value("style", std::string("circle")),
                                     marker.value("durationMs", 550)}).dump();
  return "((x, y, offsetX, offsetY, screenshot, rgb, style, durationMs) => {"
         "const scale = screenshot ? Math.max(window.devicePixelRatio || 1, 1) : 1;"
         "x /= scale; y /= scale;"
         "const appliedX = Math.min(Math.max(x + offsetX, 0), Math.max(window.innerWidth - 1, 0));"
         "const appliedY = Math.min(Math.max(y + offsetY, 0), Math.max(window.innerHeight - 1, 0));"
         "(" + std::string(kTapMarkerScript) + ")(appliedX, appliedY, rgb, style, durationMs);"
         "return {x, y, appliedX, appliedY};"
         "})(..." + arguments + ")";
}

}  // namespace

json InteractionHandler::Tap(const json& params) const {
  if (!FiniteNumber(params, "x") || !FiniteNumber(params, "y")) {
    return InvalidParams("x and y are required numbers");
  }
  const auto marker = params.value("marker", json::object());
  if (!ValidMarker(marker)) {
    return InvalidParams(
        "marker must contain only a supported style and/or an integer durationMs from 0 to 2147483647");
  }
  if (params.contains("windowId")) {
    return InvalidParams("Desktop Chromium tap targets a tab in the current window and does not accept windowId");
  }
  try {
    const auto timeout = ControlTimeout(params);
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    auto& control = RequireBrowserControl(runtime_);
    TabLease lease;
    const auto target = ResolveTabForRequest(control, params, &lease, timeout);
    if (!target.ok) return ControlError(target);
    // Keep the marker and both native input events on the resolved document.
    if (!lease.document_version && target.tab) lease.document_version = target.tab->document_version;
    const auto remaining = [&] {
      return std::chrono::duration_cast<DesktopBrowserControl::Timeout>(
          deadline - std::chrono::steady_clock::now());
    };
    const auto offsets = TapOffsets(runtime_.tap_calibration_path);
    const std::string space = params.contains("coordinateSpace")
        ? RequireString(params, "coordinateSpace") : "viewport";
    const auto script = TapMarkerExpression(params, marker, offsets, space);
    json point;
    if (remaining().count() <= 0) return ErrorResponse("TIMEOUT", "Tap timed out before drawing the marker");
    const auto evaluated = control.Evaluate(lease, script, &point, remaining());
    if (!evaluated.ok) return ControlError(evaluated);
    if (!FiniteNumber(point, "x") || !FiniteNumber(point, "y") ||
        !FiniteNumber(point, "appliedX") || !FiniteNumber(point, "appliedY")) {
      return ErrorResponse("CDP_MALFORMED_RESULT", "Tap marker did not return coordinates");
    }
    if (remaining().count() <= 0) return ErrorResponse("TIMEOUT", "Tap timed out before dispatching input");
    json input;
    const auto tapped = control.DispatchTrustedInput(
        lease, {{"type", "tap"}, {"x", point["appliedX"]}, {"y", point["appliedY"]}}, &input, remaining());
    if (!tapped.ok) return ControlError(tapped);
    point.update(offsets);
    point["input"] = std::move(input);
    if (target.tab) point["tab"] = TabJson(*target.tab);
    return SuccessResponse(point);
  } catch (const std::invalid_argument& error) {
    return InvalidParams(error.what());
  }
}

}  // namespace kelpie
