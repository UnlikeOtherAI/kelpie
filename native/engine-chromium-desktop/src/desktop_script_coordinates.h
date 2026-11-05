#pragma once
#include <cmath>
#include <optional>
#include <nlohmann/json.hpp>

namespace kelpie {
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
