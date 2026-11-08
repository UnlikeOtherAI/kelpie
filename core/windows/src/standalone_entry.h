#pragma once
#include <windows.h>

#if defined(HAS_CEF)
#include "include/cef_sandbox_win.h"
int RunKelpieBootstrap(HINSTANCE instance, LPWSTR command_line, int show_command,
                       void* sandbox_info, cef_version_info_t* version_info);
#else
int RunKelpieStandalone(HINSTANCE instance, HINSTANCE previous, PWSTR command_line, int show_command);
#endif
