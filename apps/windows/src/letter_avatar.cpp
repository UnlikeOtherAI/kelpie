#include "letter_avatar.h"

#include <array>
#include <cstdint>

// `feat/windows-theme` relocates these helpers to `theme/` behind the same
// `kelpie::windows::ui` names; only this include changes when it lands.
#include "ui_theme.h"

namespace kelpie::windows {
namespace {

// `LetterAvatarView.palette`, converted from `NSColor(calibratedHue:saturation:
// brightness:)` to 8-bit RGB. The macOS HSB source values are kept beside each
// entry so the two platforms can be compared without running a colour picker.
constexpr std::array<COLORREF, kLetterAvatarPaletteSize> kPalette = {
    RGB(86, 128, 191),   // indigo — h 0.60, s 0.55, b 0.75
    RGB(85, 166, 83),    // green  — h 0.33, s 0.50, b 0.65
    RGB(204, 133, 82),   // orange — h 0.07, s 0.60, b 0.80
    RGB(191, 96, 170),   // purple — h 0.87, s 0.50, b 0.75
    RGB(83, 159, 184),   // teal   — h 0.54, s 0.55, b 0.72
    RGB(199, 90, 109),   // rose   — h 0.97, s 0.55, b 0.78
};

// macOS uses `NSColor.systemYellow` for the start page star.
constexpr COLORREF kStartPageStarColor = RGB(255, 204, 0);

// Reference geometry from `LetterAvatarView`: a 14 pt square with a 3 pt corner
// radius and a 9 pt bold label.
constexpr int kReferenceSize = 14;
constexpr int kReferenceCornerRadius = 3;
constexpr int kReferenceFontSize = 9;

int ScaledFromReference(const RECT& bounds, int reference_value) {
  const int extent = bounds.bottom - bounds.top;
  const int scaled = MulDiv(reference_value, extent, kReferenceSize);
  return scaled < 1 ? 1 : scaled;
}

// Decodes one UTF-8 scalar starting at `index`, advancing it past the sequence.
// Malformed bytes decode as themselves so a bad host still produces a stable
// colour rather than an exception.
std::uint32_t NextScalar(std::string_view text, std::size_t& index) {
  const auto lead = static_cast<unsigned char>(text[index]);
  std::size_t length = 1;
  std::uint32_t scalar = lead;
  if ((lead & 0xE0U) == 0xC0U) {
    length = 2;
    scalar = lead & 0x1FU;
  } else if ((lead & 0xF0U) == 0xE0U) {
    length = 3;
    scalar = lead & 0x0FU;
  } else if ((lead & 0xF8U) == 0xF0U) {
    length = 4;
    scalar = lead & 0x07U;
  }
  if (index + length > text.size()) {
    ++index;
    return lead;
  }
  for (std::size_t offset = 1; offset < length; ++offset) {
    const auto continuation = static_cast<unsigned char>(text[index + offset]);
    if ((continuation & 0xC0U) != 0x80U) {
      ++index;
      return lead;
    }
    scalar = (scalar << 6U) | (continuation & 0x3FU);
  }
  index += length;
  return scalar;
}

// Swift's `Character.isLetter` is the full Unicode letter category. ASCII is
// decided exactly; every non-ASCII scalar is treated as a letter, which is right
// for host names — the only non-letter characters a host can legally contain are
// ASCII digits, dots, and hyphens.
bool IsLetterScalar(std::uint32_t scalar) {
  if (scalar < 0x80U) {
    return (scalar >= 'A' && scalar <= 'Z') || (scalar >= 'a' && scalar <= 'z');
  }
  return true;
}

HFONT CreateAvatarFont(const RECT& bounds) {
  return CreateFontW(-ScaledFromReference(bounds, kReferenceFontSize), 0, 0, 0, FW_BOLD, FALSE,
                     FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
}

void DrawCenteredGlyph(HDC device_context, const RECT& bounds, HFONT font, COLORREF color,
                       const std::wstring& text) {
  HGDIOBJ previous_font = SelectObject(device_context, font);
  const int previous_mode = SetBkMode(device_context, TRANSPARENT);
  const COLORREF previous_color = SetTextColor(device_context, color);
  RECT text_bounds = bounds;
  DrawTextW(device_context, text.c_str(), -1, &text_bounds,
            DT_CENTER | DT_SINGLELINE | DT_VCENTER | DT_NOCLIP);
  SetTextColor(device_context, previous_color);
  SetBkMode(device_context, previous_mode);
  SelectObject(device_context, previous_font);
}

}  // namespace

int LetterAvatarSize(HWND window) {
  return ui::Dip(window, kTabIconDip);
}

COLORREF LetterAvatarPaletteColor(std::size_t index) {
  return kPalette[index % kLetterAvatarPaletteSize];
}

std::size_t LetterAvatarColorIndex(std::string_view host) {
  // Swift folds with `&*` and `&+` over a 64-bit signed Int, so the arithmetic
  // is defined to wrap. Unsigned accumulation reproduces the same bit pattern
  // without relying on signed overflow, which is undefined in C++.
  std::uint64_t hash = 0;
  std::size_t index = 0;
  while (index < host.size()) {
    hash = hash * 31U + NextScalar(host, index);
  }

  // Swift then takes `abs(...)`: reinterpret as signed and negate a negative
  // result with the same wrapping arithmetic. Swift's `abs` traps on exactly
  // `Int.min`; this returns 2^63 instead of crashing, which is the only input
  // where the two platforms can disagree.
  const auto signed_hash = static_cast<std::int64_t>(hash);
  const std::uint64_t magnitude = signed_hash < 0 ? (~hash + 1U) : hash;
  return static_cast<std::size_t>(magnitude % kLetterAvatarPaletteSize);
}

COLORREF LetterAvatarColor(std::string_view host) {
  return LetterAvatarPaletteColor(LetterAvatarColorIndex(host));
}

std::wstring LetterAvatarLetter(std::string_view host) {
  std::size_t index = 0;
  while (index < host.size()) {
    const std::uint32_t scalar = NextScalar(host, index);
    if (!IsLetterScalar(scalar)) {
      continue;
    }
    if (scalar < 0x80U) {
      return std::wstring(1, static_cast<wchar_t>(scalar >= 'a' && scalar <= 'z'
                                                      ? scalar - ('a' - 'A')
                                                      : scalar));
    }
    if (scalar <= 0xFFFFU) {
      std::wstring letter(1, static_cast<wchar_t>(scalar));
      CharUpperBuffW(letter.data(), 1);
      return letter;
    }
    // Astral scalar: keep the surrogate pair as-is. Nothing outside the BMP has
    // a single-unit upper-case form that would fit a one-letter avatar anyway.
    const std::uint32_t adjusted = scalar - 0x10000U;
    return std::wstring{static_cast<wchar_t>(0xD800U + (adjusted >> 10U)),
                        static_cast<wchar_t>(0xDC00U + (adjusted & 0x3FFU))};
  }
  return L"?";
}

void DrawLetterAvatar(HDC device_context, const RECT& bounds, std::string_view host) {
  const COLORREF fill = LetterAvatarColor(host);
  // The macOS avatar has no border; `PaintRounded` needs a pen, so it gets the
  // fill colour and disappears into the shape.
  ui::PaintRounded(device_context, bounds, fill, fill,
                   ScaledFromReference(bounds, kReferenceCornerRadius));

  HFONT font = CreateAvatarFont(bounds);
  DrawCenteredGlyph(device_context, bounds, font, RGB(255, 255, 255), LetterAvatarLetter(host));
  DeleteObject(font);
}

void DrawStartPageIcon(HDC device_context, const RECT& bounds) {
  // Segoe Fluent Icons / Segoe MDL2 Assets share the FavoriteStarFill code
  // point, so one string covers Windows 10 and 11. CreateFontW falls back to
  // the MDL2 face when the Fluent one is absent.
  HFONT font = CreateFontW(-ScaledFromReference(bounds, 11), 0, 0, 0, FW_NORMAL, FALSE, FALSE,
                           FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                           CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe Fluent Icons");
  DrawCenteredGlyph(device_context, bounds, font, kStartPageStarColor, L"");
  DeleteObject(font);
}

}  // namespace kelpie::windows
