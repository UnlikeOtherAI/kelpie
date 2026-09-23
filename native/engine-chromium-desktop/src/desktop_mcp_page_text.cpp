#include "desktop_mcp_page_text.h"

#include <string>
#include <utility>

namespace kelpie::desktop_mcp {
namespace {

// One code point starting at `lead`: how many UTF-8 bytes it takes and how
// many UTF-16 code units it counts for. A stray byte counts as one unit, so a
// malformed string still has a length.
struct CodePoint {
  std::size_t bytes;
  std::size_t units;
};

CodePoint Measure(unsigned char lead) {
  if (lead >= 0xF0 && lead <= 0xF7) return {4, 2};
  if (lead >= 0xE0 && lead <= 0xEF) return {3, 1};
  if (lead >= 0xC0 && lead <= 0xDF) return {2, 1};
  return {1, 1};
}

std::size_t Utf16Length(const std::string& text) {
  std::size_t units = 0;
  for (std::size_t index = 0; index < text.size();) {
    const CodePoint point = Measure(static_cast<unsigned char>(text[index]));
    index += point.bytes;
    units += point.units;
  }
  return units;
}

// The longest prefix of at most `max_units` code units that ends on a code
// point boundary, and how many units it holds.
std::pair<std::string, std::size_t> CutToUnits(const std::string& text, std::size_t max_units) {
  std::size_t index = 0;
  std::size_t units = 0;
  while (index < text.size()) {
    const CodePoint point = Measure(static_cast<unsigned char>(text[index]));
    if (units + point.units > max_units || index + point.bytes > text.size()) break;
    index += point.bytes;
    units += point.units;
  }
  return {text.substr(0, index), units};
}

}  // namespace

nlohmann::json LimitPageText(nlohmann::json body, std::size_t max_chars) {
  if (!body.is_object() || !body.value("success", false)) return body;
  const auto text = body.find("text");
  if (text == body.end() || !text->is_string()) return body;
  const std::string original = text->get<std::string>();
  const std::size_t total = Utf16Length(original);
  if (total <= max_chars) {
    body["truncated"] = false;
    return body;
  }
  auto [kept, kept_units] = CutToUnits(original, max_chars);
  body["text"] = std::move(kept);
  body["truncated"] = true;
  body["totalChars"] = total;
  body["note"] = "Page text truncated to " + std::to_string(kept_units) + " of " + std::to_string(total) +
                 " characters. Pass a larger maxChars, or a selector for the part you need.";
  return body;
}

}  // namespace kelpie::desktop_mcp
