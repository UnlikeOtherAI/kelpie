#pragma once

#include <string>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows {

struct SettingsValues {
  int port = 8420;
  std::wstring profile_dir;
  std::wstring startup_url;
};

class SettingsView {
 public:
  bool ShowModal(HINSTANCE instance,
                 HWND owner,
                 const SettingsValues& initial_values,
                 SettingsValues& updated_values);
};

}  // namespace kelpie::windows
