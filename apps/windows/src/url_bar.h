#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows {

// Width reserved at the left of the address surface for the lock glyph.
inline constexpr int kLockGutterDip = 22;

class UrlBarDelegate {
 public:
  virtual ~UrlBarDelegate() = default;
  virtual void OnNavigateRequested(const std::string& url) = 0;
  virtual void OnBackRequested() = 0;
  virtual void OnForwardRequested() = 0;
  virtual void OnReloadRequested() = 0;
  virtual void OnOpenSettingsRequested() = 0;
  virtual std::optional<std::wstring> BestUrlCompletion(std::wstring_view typed) const = 0;
};

class UrlBar {
 public:
  bool Create(HWND parent, HINSTANCE instance, const RECT& bounds, UrlBarDelegate* delegate);
  void Resize(const RECT& bounds);
  // Rebuilds fonts and themed colours after a DPI or app-theme change.
  void RefreshTheme();
  void SetUrl(const std::wstring& url, bool force = false);
  void SetNavigationState(bool can_go_back, bool can_go_forward, bool is_loading);
  void Focus();
  bool HandleCommand(WORD control_id, WORD notification_code);
  bool DrawControl(const DRAWITEMSTRUCT& item) const;
  bool ControlColor(HDC device_context, HWND control, HBRUSH* brush) const;
  void Paint(HDC device_context) const;
  int Height() const;
  std::vector<HWND> FocusableControls() const;
  void Destroy();

 private:
  static LRESULT CALLBACK EditProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK ButtonProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                     UINT_PTR subclass_id, DWORD_PTR reference_data);
  void SetHoveredButton(HWND button);
  void CompleteAfterInsertion();
  void RejectCompletion();
  void SubmitCurrentUrl(std::optional<std::wstring_view> completion_url = std::nullopt);
  void InvalidateSurface() const;
  void RefreshFont();

  HWND parent_ = nullptr;
  UrlBarDelegate* delegate_ = nullptr;
  HWND back_button_ = nullptr;
  HWND forward_button_ = nullptr;
  HWND reload_button_ = nullptr;
  HWND bookmarks_button_ = nullptr;
  HWND history_button_ = nullptr;
  HWND network_button_ = nullptr;
  HWND settings_button_ = nullptr;
  HWND url_edit_ = nullptr;
  WNDPROC original_edit_proc_ = nullptr;
  mutable HBRUSH edit_brush_ = nullptr;
  HFONT edit_font_ = nullptr;
  HWND tooltip_ = nullptr;
  HWND hovered_button_ = nullptr;
  bool secure_ = false;
  bool setting_url_ = false;
  bool insertion_at_end_ = false;
  bool ime_composing_ = false;
  bool completion_active_ = false;
  std::wstring completion_prefix_;
  std::wstring completion_navigation_url_;
};

}  // namespace kelpie::windows
