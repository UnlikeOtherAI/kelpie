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
  // Off by default. Isolating every tab breaks ordinary browsing — a login
  // would not carry into a link-opened tab — so the shared store stays the
  // default and this is the opt-in for Nessie-style separate identities.
  bool isolate_new_tabs = false;
};

class SettingsView {
 public:
  bool ShowModal(HINSTANCE instance,
                 HWND owner,
                 const SettingsValues& initial_values,
                 SettingsValues& updated_values);
};

}  // namespace kelpie::windows
