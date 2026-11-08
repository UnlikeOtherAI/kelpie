#pragma once

#include "theme/palette.h"
#include <algorithm>
#include <cstdint>
#include <cmath>

namespace kelpie::windows::ui {

// Per-window, page-derived colors. Utility panels still follow the OS palette.
struct ChromePalette {
  COLORREF bar, caption, field, text, muted, line, hover, caption_text;
};

inline double Luminance(COLORREF color) {
  const auto channel = [](int c) {
    const double n = c / 255.0;
    return n <= 0.04045 ? n/12.92 : std::pow((n+0.055)/1.055,2.4);
  };
  return channel(GetRValue(color))*0.2126 + channel(GetGValue(color))*0.7152 + channel(GetBValue(color))*0.0722;
}

inline bool IsDark(COLORREF color) { return Luminance(color) < 0.179; }

inline ChromePalette ChromeColors(COLORREF page, bool high_contrast = HighContrast()) {
  if (high_contrast) {
    const auto p = Colors();
    return {p.canvas, p.canvas, p.surface, p.text, p.muted_text, p.border, p.surface_hover, p.text};
  }
  const bool dark = IsDark(page);
  const COLORREF ink = dark ? RGB(255, 255, 255) : RGB(0, 0, 0);
  const COLORREF navy = RGB(13, 23, 49);
  const COLORREF text = dark ? RGB(255,255,255) :
      (Luminance(page)+0.05)/(Luminance(navy)+0.05) >= 4.5 ? navy : RGB(0,0,0);
  return {page, RGB(229, 234, 243),
          Blend(dark ? RGB(255, 255, 255) : RGB(112, 135, 176), page, 0.09),
          text, Blend(text, page, 0.57), Blend(ink, page, 0.10), Blend(ink, page, 0.07), navy};
}

inline COLORREF DefaultChromeColor() {
  return DarkMode() ? RGB(32, 34, 40) : RGB(255, 255, 255);
}

class ChromeTransition {
 public:
  explicit ChromeTransition(COLORREF color = DefaultChromeColor()) : from_(color), target_(color) {}
  COLORREF Color(std::uint64_t now) const {
    const double t = std::clamp(static_cast<double>(now - start_) / 220.0, 0.0, 1.0);
    return Blend(target_, from_, t * t * (3.0 - 2.0 * t));
  }
  bool Active(std::uint64_t now) const { return from_ != target_ && now - start_ < 220; }
  bool Retarget(COLORREF color, std::uint64_t now, bool animate) {
    if (color == target_) return false;
    from_ = animate ? Color(now) : color;
    target_ = color;
    start_ = now;
    return true;
  }
 private:
  COLORREF from_, target_;
  std::uint64_t start_ = 0;
};

}  // namespace kelpie::windows::ui
