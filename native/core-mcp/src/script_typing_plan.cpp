#include "kelpie/browser_gateway_c_api.h"
#include <nlohmann/json.hpp>
#include <cstdint>
#include <cstring>
#include <new>
#include <string>

namespace {
using Json = nlohmann::json;
char* Copy(const Json& value) {
  const std::string text = value.dump();
  char* result = new (std::nothrow) char[text.size() + 1];
  if (result) std::memcpy(result, text.c_str(), text.size() + 1);
  return result;
}
Json Invalid() { return {{"valid", false}, {"error", "INVALID_PACED_TYPING"}}; }

// Split only valid UTF-8 Unicode scalar values; reject overlong encodings,
// surrogate code points and values above U+10FFFF before producing a plan.
bool Scalars(const std::string& text, Json* output) {
  *output = Json::array();
  for (std::size_t offset = 0; offset < text.size();) {
    const auto first = static_cast<unsigned char>(text[offset]);
    std::size_t length = 0;
    std::uint32_t value = 0, minimum = 0;
    if (first <= 0x7f) { length = 1; value = first; }
    else if (first >= 0xc2 && first <= 0xdf) { length = 2; value = first & 0x1f; minimum = 0x80; }
    else if (first >= 0xe0 && first <= 0xef) { length = 3; value = first & 0x0f; minimum = 0x800; }
    else if (first >= 0xf0 && first <= 0xf4) { length = 4; value = first & 0x07; minimum = 0x10000; }
    else return false;
    if (offset + length > text.size()) return false;
    for (std::size_t i = 1; i < length; ++i) {
      const auto next = static_cast<unsigned char>(text[offset + i]);
      if ((next & 0xc0) != 0x80) return false;
      value = (value << 6) | (next & 0x3f);
    }
    if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return false;
    output->push_back(text.substr(offset, length));
    if (output->size() > 1000) return false;
    offset += length;
  }
  return true;
}
}

extern "C" char* kelpie_browser_script_typing_plan(const char* input) {
  try {
    if (!input || std::strlen(input) > 100000) return Copy(Invalid());
    const auto request = Json::parse(input, nullptr, false);
    if (!request.is_object() || request.size() != 3 ||
        !request.contains("action") || !request["action"].is_string() ||
        !request.contains("text") || !request["text"].is_string() ||
        !request.contains("typingDelayMs") || !request["typingDelayMs"].is_number_integer()) return Copy(Invalid());
    const auto action = request["action"].get<std::string>();
    const auto delay = request["typingDelayMs"].get<std::int64_t>();
    if ((action != "fill" && action != "type") || delay < 1 || delay > 1000) return Copy(Invalid());
    Json scalars;
    if (!Scalars(request["text"].get<std::string>(), &scalars)) return Copy(Invalid());
    const auto intervals = scalars.empty() ? 0 : scalars.size() - 1;
    if (intervals * static_cast<std::size_t>(delay) > 60000) return Copy(Invalid());
    return Copy({{"valid", true}, {"clearFirst", action == "fill"},
                 {"typingDelayMs", delay}, {"scalars", std::move(scalars)}});
  } catch (...) { return Copy(Invalid()); }
}
