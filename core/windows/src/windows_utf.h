#pragma once

#include <limits>
#include <optional>
#include <string>
#include <string_view>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows::utf {

inline bool FitsWin32Length(std::size_t length) {
  return length <= static_cast<std::size_t>(std::numeric_limits<int>::max());
}

// Use this for protocol values, URLs and filesystem paths. They must be valid Unicode.
inline std::optional<std::wstring> Utf8ToWide(std::string_view value) {
  if (value.empty()) {
    return std::wstring{};
  }
  if (!FitsWin32Length(value.size())) {
    return std::nullopt;
  }
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return std::nullopt;
  }
  std::wstring output(static_cast<std::size_t>(length), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
                          output.data(), length) != length) {
    return std::nullopt;
  }
  return output;
}

// Chrome strings are display-only. Preserve valid text and replace malformed input visibly.
inline std::wstring Utf8ToWideDisplay(std::string_view value) {
  if (const auto converted = Utf8ToWide(value)) {
    return *converted;
  }
  if (value.empty() || !FitsWin32Length(value.size())) {
    return L"\uFFFD";
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return L"\uFFFD";
  }
  std::wstring output(static_cast<std::size_t>(length), L'\0');
  if (MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), output.data(), length) != length) {
    return L"\uFFFD";
  }
  return output;
}

inline bool IsHighSurrogate(wchar_t value) { return value >= 0xD800 && value <= 0xDBFF; }
inline bool IsLowSurrogate(wchar_t value) { return value >= 0xDC00 && value <= 0xDFFF; }

inline std::optional<std::string> WideToUtf8(std::wstring_view value) {
  if (!FitsWin32Length(value.size())) {
    return std::nullopt;
  }
  for (std::size_t index = 0; index < value.size(); ++index) {
    if (IsHighSurrogate(value[index])) {
      if (index + 1 == value.size() || !IsLowSurrogate(value[index + 1])) {
        return std::nullopt;
      }
      ++index;
    } else if (IsLowSurrogate(value[index])) {
      return std::nullopt;
    }
  }
  if (value.empty()) {
    return std::string{};
  }
  const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) {
    return std::nullopt;
  }
  std::string output(static_cast<std::size_t>(length), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
                          output.data(), length, nullptr, nullptr) != length) {
    return std::nullopt;
  }
  return output;
}

inline std::string WideToUtf8Display(std::wstring_view value) {
  std::wstring normalized;
  normalized.reserve(value.size());
  for (std::size_t index = 0; index < value.size(); ++index) {
    const wchar_t unit = value[index];
    if (IsHighSurrogate(unit) && index + 1 < value.size() && IsLowSurrogate(value[index + 1])) {
      normalized.push_back(unit);
      normalized.push_back(value[++index]);
    } else if (IsHighSurrogate(unit) || IsLowSurrogate(unit)) {
      normalized.append(L"\uFFFD");
    } else {
      normalized.push_back(unit);
    }
  }
  return WideToUtf8(normalized).value_or("\xEF\xBF\xBD");
}

}  // namespace kelpie::windows::utf
