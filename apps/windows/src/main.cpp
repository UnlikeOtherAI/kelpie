#include "standalone_entry.h"

#if defined(HAS_CEF)
extern "C" __declspec(dllexport) int RunWinMain(HINSTANCE instance, LPWSTR command_line,
    int show_command, void* sandbox_info, cef_version_info_t* version_info) {
  return RunKelpieBootstrap(instance, command_line, show_command, sandbox_info, version_info);
}
#else
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command_line, int show_command) {
  return RunKelpieStandalone(instance, previous, command_line, show_command);
}
#endif
