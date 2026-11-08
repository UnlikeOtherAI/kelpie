#pragma once
#include <windows.h>

#if defined(HAS_CEF)
#include "include/cef_sandbox_win.h"

namespace kelpie::windows {
using BrowserHostMain = int (*)(HINSTANCE resources, HINSTANCE process,
                               PWSTR command_line, int show_command, void* sandbox_info);

// Call from the DLL entry exported to CEF's matching sandboxed bootstrap.
// The callback runs only in the browser process after subprocess dispatch.
int BootstrapBrowserHost(HINSTANCE instance, LPWSTR command_line, int show_command,
                         void* sandbox_info, cef_version_info_t* version_info,
                         BrowserHostMain host_main);
}
#endif
