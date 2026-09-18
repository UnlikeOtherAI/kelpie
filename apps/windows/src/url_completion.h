#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>

namespace kelpie::windows::completion {

inline bool IsTextInsertionAtEnd(bool ime_composing,
                                 std::size_t text_length,
                                 std::size_t selection_start,
                                 std::size_t selection_end,
                                 wchar_t character) {
  return !ime_composing && selection_start == selection_end && selection_end == text_length &&
         character >= L' ' && character != 0x7F;
}

inline bool IsStrictSuffix(std::wstring_view typed, std::wstring_view candidate) {
  return candidate.size() > typed.size() && candidate.compare(0, typed.size(), typed) == 0;
}

inline wchar_t FoldAscii(wchar_t character) {
  return character >= L'A' && character <= L'Z' ? static_cast<wchar_t>(character + (L'a' - L'A')) : character;
}

inline bool HasAsciiPrefix(std::wstring_view value, std::wstring_view prefix) {
  if (value.size() < prefix.size()) return false;
  for (std::size_t index = 0; index < prefix.size(); ++index) {
    if (FoldAscii(value[index]) != FoldAscii(prefix[index])) return false;
  }
  return true;
}

inline std::optional<std::wstring> DisplayCandidate(std::wstring_view typed,
                                                    std::wstring_view canonical_url) {
  if (typed.empty()) return std::nullopt;
  const auto complete = [typed](std::wstring_view form) -> std::optional<std::wstring> {
    if (form.size() <= typed.size() || !HasAsciiPrefix(form, typed)) return std::nullopt;
    return std::wstring(typed) + std::wstring(form.substr(typed.size()));
  };
  if (const auto direct = complete(canonical_url)) return direct;

  constexpr std::wstring_view kHttp = L"http://";
  constexpr std::wstring_view kHttps = L"https://";
  constexpr std::wstring_view kWww = L"www.";
  std::wstring_view without_scheme = canonical_url;
  std::wstring_view scheme;
  if (HasAsciiPrefix(canonical_url, kHttps)) {
    scheme = kHttps;
    without_scheme.remove_prefix(kHttps.size());
  } else if (HasAsciiPrefix(canonical_url, kHttp)) {
    scheme = kHttp;
    without_scheme.remove_prefix(kHttp.size());
  } else {
    return std::nullopt;
  }
  if (HasAsciiPrefix(without_scheme, kWww)) {
    const std::wstring scheme_without_www = std::wstring(scheme) + std::wstring(without_scheme.substr(kWww.size()));
    if (const auto scheme_preserved = complete(scheme_without_www)) return scheme_preserved;
  }
  if (const auto scheme_stripped = complete(without_scheme)) return scheme_stripped;
  if (HasAsciiPrefix(without_scheme, kWww)) {
    return complete(without_scheme.substr(kWww.size()));
  }
  return std::nullopt;
}

}  // namespace kelpie::windows::completion
