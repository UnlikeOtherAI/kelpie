#include <string>

#include "windows_utf.h"
#include "url_completion.h"

namespace {

bool Expect(bool value) { return value; }

}  // namespace

int main() {
  using kelpie::windows::utf::Utf8ToWide;
  using kelpie::windows::utf::Utf8ToWideDisplay;
  using kelpie::windows::utf::WideToUtf8;
  using kelpie::windows::utf::WideToUtf8Display;
  using kelpie::windows::completion::IsStrictSuffix;
  using kelpie::windows::completion::IsTextInsertionAtEnd;
  using kelpie::windows::completion::DisplayCandidate;

  const std::string snowman = "https://example.test/\xE2\x98\x83";
  const auto wide = Utf8ToWide(snowman);
  if (!Expect(wide.has_value()) || !Expect(WideToUtf8(*wide) == snowman)) return 1;
  if (!Expect(!Utf8ToWide("\xC3\x28").has_value())) return 2;
  if (!Expect(!WideToUtf8(std::wstring(1, static_cast<wchar_t>(0xD800))).has_value())) return 3;
  const std::wstring display = Utf8ToWideDisplay("\xC3\x28");
  if (!Expect(display.find(L'\uFFFD') != std::wstring::npos)) return 4;
  if (!Expect(WideToUtf8Display(std::wstring(1, static_cast<wchar_t>(0xDC00))) == "\xEF\xBF\xBD")) return 5;
  if (!Expect(IsTextInsertionAtEnd(false, 4, 4, 4, L'x'))) return 6;
  if (!Expect(!IsTextInsertionAtEnd(false, 4, 2, 4, L'x'))) return 7;
  if (!Expect(!IsTextInsertionAtEnd(false, 4, 4, 4, L'\b'))) return 8;
  if (!Expect(!IsTextInsertionAtEnd(true, 4, 4, 4, L'x'))) return 9;
  if (!Expect(IsStrictSuffix(L"https://exa", L"https://example.test"))) return 10;
  if (!Expect(!IsStrictSuffix(L"https://exa", std::wstring(L"https://exa")))) return 11;
  // History remains canonical; only the Windows display layer hides compatible prefixes.
  if (!Expect(DisplayCandidate(L"exa", L"https://www.example.test/\u2603") == L"example.test/\u2603")) return 12;
  if (!Expect(DisplayCandidate(L"www.exa", L"https://www.example.test") == L"www.example.test")) return 13;
  if (!Expect(DisplayCandidate(L"https://exa", L"https://www.example.test") == L"https://example.test")) return 14;
  if (!Expect(!DisplayCandidate(L"http://exa", L"https://example.test").has_value())) return 15;
  if (!Expect(DisplayCandidate(L"EXA", L"https://www.Example.test") == L"EXAmple.test")) return 16;
  return 0;
}
