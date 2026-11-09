#include "network_rows.h"

#include <algorithm>
#include <cwctype>

#include <nlohmann/json.hpp>

#include "display_format.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {

// Requests a page script made are Fetch/XHR whatever they returned; the rest
// sort by the store's content category, as DevTools sorts by resource type.
RequestType BucketFor(const std::string& category, bool from_script) {
  if (from_script) return RequestType::kFetch;
  if (category == "HTML") return RequestType::kDoc;
  if (category == "CSS") return RequestType::kCss;
  if (category == "JS") return RequestType::kJs;
  if (category == "Font") return RequestType::kFont;
  if (category == "Image") return RequestType::kImg;
  return RequestType::kOther;
}

std::wstring TypeName(const std::string& category, bool from_script) {
  if (from_script) return L"fetch";
  if (category == "HTML") return L"document";
  if (category == "CSS") return L"stylesheet";
  if (category == "JS") return L"script";
  if (category == "Image") return L"image";
  if (category == "Font") return L"font";
  if (category == "JSON") return L"json";
  if (category == "XML") return L"xml";
  return L"other";
}

std::wstring Lower(std::wstring_view text) {
  std::wstring result(text);
  std::transform(result.begin(), result.end(), result.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return result;
}

}  // namespace

std::vector<NetworkRow> ParseNetworkRows(const std::string& json) {
  std::vector<NetworkRow> rows;
  const auto parsed = nlohmann::json::parse(json, nullptr, false);
  if (!parsed.is_array()) return rows;
  rows.reserve(parsed.size());
  for (const auto& entry : parsed) {
    if (!entry.is_object()) continue;
    const std::string url = entry.value("url", "");
    const std::string category = entry.value("category", "Other");
    const bool from_script = entry.value("initiator", "browser") == "js";
    const int status = entry.value("status_code", 0);
    const std::int64_t bytes = entry.value("size", static_cast<std::int64_t>(0));
    NetworkRow row;
    row.id = entry.value("id", "");
    row.name = format::RequestName(url);
    row.url = utf::Utf8ToWideDisplay(url);
    row.method = utf::Utf8ToWideDisplay(entry.value("method", "GET"));
    row.type = TypeName(category, from_script);
    row.initiator = from_script ? L"script" : L"browser";
    row.status = status == 0 ? L"(failed)" : std::to_wstring(status);
    row.size = format::Bytes(bytes);
    row.time = format::Duration(entry.value("duration", static_cast<std::int64_t>(0)));
    row.bucket = BucketFor(category, from_script);
    row.bytes = bytes;
    row.failed = status == 0 || status >= 400;
    rows.push_back(std::move(row));
  }
  return rows;
}

std::vector<std::size_t> FilterNetworkRows(const std::vector<NetworkRow>& rows, RequestType type,
                                           std::wstring_view text) {
  const std::wstring needle = Lower(text);
  std::vector<std::size_t> matches;
  for (std::size_t index = 0; index < rows.size(); ++index) {
    const auto& row = rows[index];
    if (type != RequestType::kAll && row.bucket != type) continue;
    if (!needle.empty() && Lower(row.url).find(needle) == std::wstring::npos &&
        Lower(row.method).find(needle) == std::wstring::npos) {
      continue;
    }
    matches.push_back(index);
  }
  return matches;
}

}  // namespace kelpie::windows
