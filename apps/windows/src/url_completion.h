#pragma once

#include <cstddef>
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

}  // namespace kelpie::windows::completion
