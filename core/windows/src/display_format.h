#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace kelpie::windows::format {

// The short request name DevTools shows: the last path segment with its
// query, or the host when the path is empty ("example.com" for
// "https://example.com/").
std::wstring RequestName(std::string_view url);

// Transfer sizes in decimal units, as DevTools prints them: "512 B",
// "1.6 kB", "2.4 MB". Zero is "0 B".
std::wstring Bytes(std::int64_t bytes);

// "57 ms" below a second, "1.24 s" from there; negative durations print
// as "0 ms".
std::wstring Duration(std::int64_t milliseconds);

// An ISO 8601 UTC stamp ("2026-11-09T10:05:30Z", fraction optional) in the
// person's short date and time format and local time zone. Anything that does
// not parse is returned unchanged rather than hidden.
std::wstring LocalTime(std::string_view iso8601);

}  // namespace kelpie::windows::format
