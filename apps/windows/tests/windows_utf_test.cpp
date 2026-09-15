#include <string>

#include "windows_utf.h"

namespace {

bool Expect(bool value) { return value; }

}  // namespace

int main() {
  using kelpie::windows::utf::Utf8ToWide;
  using kelpie::windows::utf::Utf8ToWideDisplay;
  using kelpie::windows::utf::WideToUtf8;
  using kelpie::windows::utf::WideToUtf8Display;

  const std::string snowman = "https://example.test/\xE2\x98\x83";
  const auto wide = Utf8ToWide(snowman);
  if (!Expect(wide.has_value()) || !Expect(WideToUtf8(*wide) == snowman)) return 1;
  if (!Expect(!Utf8ToWide("\xC3\x28").has_value())) return 2;
  if (!Expect(!WideToUtf8(std::wstring(1, static_cast<wchar_t>(0xD800))).has_value())) return 3;
  const std::wstring display = Utf8ToWideDisplay("\xC3\x28");
  if (!Expect(display.find(L'\uFFFD') != std::wstring::npos)) return 4;
  if (!Expect(WideToUtf8Display(std::wstring(1, static_cast<wchar_t>(0xDC00))) == "\xEF\xBF\xBD")) return 5;
  return 0;
}
