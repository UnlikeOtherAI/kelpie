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
  }
  content.push_back({{"type", "text"}, {"text", text.dump()}});
  return {{"content", content}, {"isError", !response.value("ok", false)}};
}
}
