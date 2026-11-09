#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace kelpie::windows {

// The request-type buttons of the network panel, in the order DevTools uses.
enum class RequestType { kAll, kFetch, kDoc, kCss, kJs, kFont, kImg, kOther };

struct RequestTypeLabel {
  RequestType type;
  const wchar_t* label;
};

inline constexpr std::array<RequestTypeLabel, 8> kRequestTypes{{
    {RequestType::kAll, L"All"},
    {RequestType::kFetch, L"Fetch/XHR"},
    {RequestType::kDoc, L"Doc"},
    {RequestType::kCss, L"CSS"},
    {RequestType::kJs, L"JS"},
    {RequestType::kFont, L"Font"},
    {RequestType::kImg, L"Img"},
    {RequestType::kOther, L"Other"},
}};

// One recorded request, already shaped for the table.
struct NetworkRow {
  std::string id;
  std::wstring name;     // last path segment, see format::RequestName
  std::wstring url;      // the full address, for the tooltip and the filter
  std::wstring method;
  std::wstring type;     // "document", "script", "fetch", ...
  std::wstring initiator;
  std::wstring status;   // "200", or "(failed)" when no response arrived
  std::wstring size;
  std::wstring time;
  RequestType bucket = RequestType::kOther;
  std::int64_t bytes = 0;
  bool failed = false;   // no response, or a 4xx/5xx answer
};

// Parses the network store's JSON (oldest first). Malformed input is empty.
std::vector<NetworkRow> ParseNetworkRows(const std::string& json);

// Indices of the rows that belong to `type` and whose address or method
// contains `text`, ignoring case. An empty `text` keeps every row of the type.
std::vector<std::size_t> FilterNetworkRows(const std::vector<NetworkRow>& rows, RequestType type,
                                           std::wstring_view text);

}  // namespace kelpie::windows
