#pragma once
#include <cmath>
#include <optional>
#include <nlohmann/json.hpp>

namespace kelpie {
// Across-frame gutters can change visible size. Actual source dimensions are
// independently checked by the capture adapter; within-frame metrics are exact.
inline bool ScriptCaptureViewportCompatible(const nlohmann::json& previous,
    const nlohmann::json& current,bool same_document) {
  try {
    for(const char* key:{"width","height"})
      if(previous.at(key)!=current.at(key)) return false;
    if(same_document) for(const char* key:{"offsetLeft","offsetTop","scale"})
      if(previous.at("visualViewport").at(key)!=current.at("visualViewport").at(key)) return false;
    return true;
  }catch(const std::exception&){return false;}
}
// Called only after the fixed renderer inspection has been attempted.
inline bool ScriptTargetInspectionExplicit(const nlohmann::json& value) {
  return value.is_object() && value.contains("ok") && value["ok"].is_boolean() &&
    value.contains("sensitive") && value["sensitive"].is_boolean();
}
inline bool ScriptTargetPostMutationExplicit(const nlohmann::json& value) {
  if (!ScriptTargetInspectionExplicit(value) || !value.contains("sensitivityKnown") ||
      !value["sensitivityKnown"].is_boolean()) return false;
  if (value["ok"].get<bool>()) return !value.contains("error");
  return value.contains("error") && value["error"].is_string() && !value["error"].get<std::string>().empty();
}
inline bool ScriptTargetInspectionUncertain(const nlohmann::json& value) {
  return !ScriptTargetInspectionExplicit(value) || (!value["sensitive"].get<bool>() &&
    (!value.contains("sensitivityKnown") || !value["sensitivityKnown"].is_boolean() || !value["sensitivityKnown"].get<bool>()));
}
struct DesktopScriptCdpPoint {double x,y;};
// CDP already applies page scale. Its viewport CSS coordinates exclude only
// the captured visual offset; renderer-pixel and DPR transforms belong to UI.
inline std::optional<DesktopScriptCdpPoint> ScriptTargetCdpPoint(const nlohmann::json& target) {
  try {
    const auto& view=target.at("visualViewport");
    const double x=target.at("x"),y=target.at("y");
    const double left=view.at("offsetLeft"),top=view.at("offsetTop");
    const double width=view.at("width"),height=view.at("height"),scale=view.at("scale");
    if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(left)||!std::isfinite(top)||
       !std::isfinite(width)||!std::isfinite(height)||!std::isfinite(scale)||
       width<=0||height<=0||scale<=0)return std::nullopt;
    const double relative_x=x-left,relative_y=y-top;
    if(relative_x<0||relative_y<0||relative_x>=width||relative_y>=height)return std::nullopt;
    return DesktopScriptCdpPoint{relative_x,relative_y};
  }catch(const std::exception&){return std::nullopt;}
}
}
