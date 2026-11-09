#include "display_format.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <cstdio>

#include "windows_utf.h"

namespace kelpie::windows::format {
namespace {

bool ReadNumber(std::string_view text, std::size_t offset, std::size_t digits, WORD* value) {
  if (offset + digits > text.size()) return false;
  WORD result = 0;
  for (std::size_t index = offset; index < offset + digits; ++index) {
    const char c = text[index];
    if (c < '0' || c > '9') return false;
    result = static_cast<WORD>(result * 10 + (c - '0'));
  }
  *value = result;
  return true;
}

std::wstring Decimal(double value, const wchar_t* unit) {
  wchar_t buffer[32]{};
  swprintf_s(buffer, value < 10.0 ? L"%.1f %s" : L"%.0f %s", value, unit);
  return buffer;
}

}  // namespace

std::wstring RequestName(std::string_view url) {
  std::string_view rest = url;
  const auto scheme = rest.find("://");
  if (scheme == std::string_view::npos) return utf::Utf8ToWideDisplay(std::string(url));
  rest.remove_prefix(scheme + 3);
  const auto path_start = rest.find_first_of("/?#");
  const std::string_view host = rest.substr(0, path_start);
  if (path_start == std::string_view::npos) return utf::Utf8ToWideDisplay(std::string(host));
  std::string_view path = rest.substr(path_start);
  const auto fragment = path.find('#');
  if (fragment != std::string_view::npos) path = path.substr(0, fragment);
  const auto query = path.find('?');
  std::string_view segments = path.substr(0, query);
  const std::string_view search = query == std::string_view::npos ? std::string_view() : path.substr(query);
  while (!segments.empty() && segments.back() == '/') segments.remove_suffix(1);
  const auto slash = segments.rfind('/');
  const std::string_view last = slash == std::string_view::npos ? segments : segments.substr(slash + 1);
  if (last.empty()) return utf::Utf8ToWideDisplay(std::string(host) + std::string(search));
  return utf::Utf8ToWideDisplay(std::string(last) + std::string(search));
}

std::wstring Bytes(std::int64_t bytes) {
  if (bytes < 1000) return std::to_wstring(bytes < 0 ? 0 : bytes) + L" B";
  const double value = static_cast<double>(bytes);
  if (bytes < 1000 * 1000) return Decimal(value / 1000.0, L"kB");
  return Decimal(value / (1000.0 * 1000.0), L"MB");
}

std::wstring Duration(std::int64_t milliseconds) {
  if (milliseconds < 1000) return std::to_wstring(milliseconds < 0 ? 0 : milliseconds) + L" ms";
  wchar_t buffer[32]{};
  swprintf_s(buffer, L"%.2f s", static_cast<double>(milliseconds) / 1000.0);
  return buffer;
}

std::wstring LocalTime(std::string_view iso8601) {
  SYSTEMTIME utc{};
  // YYYY-MM-DDTHH:MM:SS, then an optional fraction and a Z.
  const bool parsed = iso8601.size() >= 19 && iso8601[4] == '-' && iso8601[7] == '-' &&
                      (iso8601[10] == 'T' || iso8601[10] == ' ') && iso8601[13] == ':' &&
                      iso8601[16] == ':' && ReadNumber(iso8601, 0, 4, &utc.wYear) &&
                      ReadNumber(iso8601, 5, 2, &utc.wMonth) && ReadNumber(iso8601, 8, 2, &utc.wDay) &&
                      ReadNumber(iso8601, 11, 2, &utc.wHour) &&
                      ReadNumber(iso8601, 14, 2, &utc.wMinute) &&
                      ReadNumber(iso8601, 17, 2, &utc.wSecond);
  SYSTEMTIME local{};
  FILETIME check{};
  if (!parsed || !SystemTimeToFileTime(&utc, &check) ||
      !SystemTimeToTzSpecificLocalTime(nullptr, &utc, &local)) {
    return utf::Utf8ToWideDisplay(std::string(iso8601));
  }
  wchar_t date[64]{};
  wchar_t time[64]{};
  if (GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, DATE_SHORTDATE, &local, nullptr, date, 64, nullptr) == 0 ||
      GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &local, nullptr, time, 64) == 0) {
    return utf::Utf8ToWideDisplay(std::string(iso8601));
  }
  return std::wstring(date) + L"  " + time;
}

}  // namespace kelpie::windows::format
