#include "kelpie/browser_gateway.h"
namespace kelpie {
using json = nlohmann::json;
json BrowserMcpResult(const json& response) {
  json text = response;
  json content = json::array();
  if (response.value("ok", false) && response.contains("value") && response["value"].is_object() && response["value"].value("type", std::string()) == "image") {
    const auto& value = response["value"];
    content.push_back({{"type", "image"}, {"mimeType", value.at("mimeType")}, {"data", value.at("data")}});
    text["value"].erase("data");
  } else if (response.value("ok", false) && response.contains("value") && response["value"].is_object() &&
      response["value"].contains("image") && response["value"]["image"].is_string()) {
    const auto& value = response["value"];
    const std::string format = value.value("format", std::string("png"));
    const std::string mime = format == "jpg" || format == "jpeg" ? "image/jpeg" : format == "webp" ? "image/webp" : "image/png";
    content.push_back({{"type", "image"}, {"mimeType", mime}, {"data", value["image"]}});
    text["value"].erase("image");
  }
  content.push_back({{"type", "text"}, {"text", text.dump()}});
  return {{"content", content}, {"isError", !response.value("ok", false)}};
}
}
