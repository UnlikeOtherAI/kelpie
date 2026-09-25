#pragma once

#include <functional>
#include <string>
#include <vector>
#include "theme/chrome_palette.h"

namespace kelpie::windows {

class FavoritesBar {
 public:
  void Attach(HWND parent, HINSTANCE instance, std::function<void(const std::string&)> navigate);
  bool Update(const std::string& json);
  void Layout(RECT bounds);
  int Height() const;
  bool DrawControl(const DRAWITEMSTRUCT& item) const;
  bool HandleCommand(UINT id);
  void SetPalette(ui::ChromePalette palette) { palette_ = palette; }
  std::vector<HWND> FocusableControls() const;
 private:
  struct Favorite { std::wstring title; std::string url; HWND button; };
  HWND parent_ = nullptr, overflow_ = nullptr;
  HINSTANCE instance_ = nullptr;
  std::string json_;
  std::vector<Favorite> items_;
  std::size_t visible_ = 0;
  std::function<void(const std::string&)> navigate_;
  ui::ChromePalette palette_ = ui::ChromeColors(ui::DefaultChromeColor());
};

}  // namespace kelpie::windows
