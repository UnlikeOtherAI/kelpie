#pragma once
#include <functional>
#include <string>

namespace kelpie::account {
enum class LoginSurface { kNone, kAppWindow, kSystemBrowser };
using LoginOpener = std::function<bool(const std::string&)>;

// Opens the UOA login/register URL. The in-app window comes first because it
// shares the default browser profile with tabs, so a Google sign-in done for
// UOA also signs every tab in. The system browser is only the fallback when
// the window is not allowed (e.g. headless) or could not be opened.
LoginSurface OpenLoginSurface(const std::string& url, bool app_window_allowed,
                              const LoginOpener& app_window, const LoginOpener& system_browser);
}  // namespace kelpie::account
