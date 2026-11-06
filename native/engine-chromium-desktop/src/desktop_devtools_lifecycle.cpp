#include "desktop_devtools.h"

namespace kelpie {
void DesktopDevToolsSession::OnDevToolsAgentDetached(CefRefPtr<CefBrowser> browser) {
#if defined(KELPIE_WINDOWS_CEF_STREAM_PROBE)
  bool owned = false;
  { std::lock_guard<std::mutex> lock(mutex_); owned = browser_ && browser && browser_->IsSame(browser); }
  if (owned) ClearTestStream();
#else
  (void)browser;
#endif
  // Detaching a transport does not prove JavaScript stopped. Preserve ownership
  // until the owning tab's confirmed OnBeforeClose callback calls CancelAll().
}

}  // namespace kelpie
