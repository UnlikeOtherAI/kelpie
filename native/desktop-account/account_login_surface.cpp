#include "account_login_surface.h"

namespace kelpie::account {
LoginSurface OpenLoginSurface(const std::string& url, bool app_window_allowed,
                              const LoginOpener& app_window, const LoginOpener& system_browser) {
  if (app_window_allowed && app_window && app_window(url)) return LoginSurface::kAppWindow;
  if (system_browser && system_browser(url)) return LoginSurface::kSystemBrowser;
  return LoginSurface::kNone;
}
}  // namespace kelpie::account
