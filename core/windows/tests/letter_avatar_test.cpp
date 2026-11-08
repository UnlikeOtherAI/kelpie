#include <cassert>
#include <cstdlib>
#include <iostream>
#include <set>
#include <string>

#include "letter_avatar.h"

using kelpie::windows::LetterAvatarColor;
using kelpie::windows::LetterAvatarColorIndex;
using kelpie::windows::LetterAvatarLetter;
using kelpie::windows::LetterAvatarPaletteColor;

namespace {

// Expected indices computed from the macOS hash
// `abs(domain.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % 6`.
// A change to either platform's hash must break this test.
std::size_t ReferenceIndex(const std::string& host) {
  unsigned long long hash = 0;
  for (unsigned char character : host) {
    hash = hash * 31U + character;
  }
  const auto signed_hash = static_cast<long long>(hash);
  const unsigned long long magnitude = signed_hash < 0 ? (~hash + 1U) : hash;
  return static_cast<std::size_t>(magnitude % 6U);
}

void TestPaletteMatchesMacOs() {
  // `LetterAvatarView.palette`, HSB converted to RGB.
  assert(LetterAvatarPaletteColor(0) == RGB(86, 128, 191));
  assert(LetterAvatarPaletteColor(1) == RGB(85, 166, 83));
  assert(LetterAvatarPaletteColor(2) == RGB(204, 133, 82));
  assert(LetterAvatarPaletteColor(3) == RGB(191, 96, 170));
  assert(LetterAvatarPaletteColor(4) == RGB(83, 159, 184));
  assert(LetterAvatarPaletteColor(5) == RGB(199, 90, 109));

  // Six distinct colours, and the index wraps rather than reading past the end.
  std::set<COLORREF> distinct;
  for (std::size_t index = 0; index < 6; ++index) {
    distinct.insert(LetterAvatarPaletteColor(index));
  }
  assert(distinct.size() == 6);
  assert(LetterAvatarPaletteColor(6) == LetterAvatarPaletteColor(0));
  assert(LetterAvatarPaletteColor(13) == LetterAvatarPaletteColor(1));
}

void TestHashMatchesMacOs() {
  const std::string hosts[] = {"example.com",  "github.com",   "www.google.com", "localhost",
                               "news.ycombinator.com", "a",     "",              "127.0.0.1",
                               "kelpie.example.test",  "xn--80ak6aa92e.com"};
  for (const std::string& host : hosts) {
    assert(LetterAvatarColorIndex(host) == ReferenceIndex(host));
    assert(LetterAvatarColorIndex(host) < 6);
    assert(LetterAvatarColor(host) == LetterAvatarPaletteColor(ReferenceIndex(host)));
  }

  // Deterministic: the same host always lands on the same colour.
  assert(LetterAvatarColorIndex("example.com") == LetterAvatarColorIndex("example.com"));

  // A long host must not overflow into a different result on a rerun.
  const std::string long_host(512, 'z');
  assert(LetterAvatarColorIndex(long_host) == ReferenceIndex(long_host));

  // Multi-byte UTF-8 is folded by Unicode scalar, not by byte: "é" is one
  // scalar (0xE9), so the hash matches Swift's rather than the two UTF-8 bytes.
  const std::size_t expected = static_cast<std::size_t>((0xE9ULL * 31U + 'a') % 6U);
  assert(LetterAvatarColorIndex("\xC3\xA9"
                                "a") == expected);
}

void TestLetterSelection() {
  assert(LetterAvatarLetter("example.com") == L"E");
  assert(LetterAvatarLetter("github.com") == L"G");
  // `first(where: { $0.isLetter })` skips digits and punctuation.
  assert(LetterAvatarLetter("127.0.0.1") == L"?");
  assert(LetterAvatarLetter("3m.com") == L"M");
  assert(LetterAvatarLetter("...x") == L"X");
  // No letter at all falls back to "?", matching macOS.
  assert(LetterAvatarLetter("") == L"?");
  assert(LetterAvatarLetter("...") == L"?");
  // Non-ASCII hosts keep a letter rather than degrading to "?".
  assert(LetterAvatarLetter("\xC3\xA9xample.test") == L"É");
}

void TestPaintsWithoutLeakingObjects() {
  // A hidden DC is enough to exercise the paint path. Every brush, pen, and font
  // the avatar creates must be released, or the strip would burn a GDI handle on
  // every repaint.
  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP surface = CreateCompatibleBitmap(screen, 32, 32);
  HGDIOBJ previous = SelectObject(memory, surface);
  const RECT bounds{0, 0, 14, 14};

  const auto paint = [&](int iterations) {
    for (int iteration = 0; iteration < iterations; ++iteration) {
      kelpie::windows::DrawLetterAvatar(memory, bounds, "example.com");
      kelpie::windows::DrawStartPageIcon(memory, bounds);
    }
  };

  // Warm up first: GDI grows its own font and brush caches on first use, and
  // that one-off growth is not a leak. What matters is that repeating the work
  // afterwards adds nothing.
  paint(20);
  const DWORD warm = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  paint(500);
  const DWORD after = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  assert(after <= warm);

  SelectObject(memory, previous);
  DeleteObject(surface);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
}

}  // namespace

int main() {
  // A failed assert must print and exit, never raise the CRT's modal dialog:
  // under CTest that dialog hangs the run instead of failing it.
#if defined(_MSC_VER)
  _set_error_mode(_OUT_TO_STDERR);
  _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
#endif

  TestPaletteMatchesMacOs();
  TestHashMatchesMacOs();
  TestLetterSelection();
  TestPaintsWithoutLeakingObjects();
  std::cout << "letter avatar tests passed" << std::endl;
  return 0;
}
