#include "linux_app.h"
#if KELPIE_LINUX_HAS_CEF
#include "linux_desktop_internal.h"
#include "script_capture_service.h"
#endif
namespace kelpie::linuxapp {
LinuxApp::json LinuxApp::ScriptPresentation(bool foreground) const {
  (void)foreground;
#if KELPIE_LINUX_HAS_CEF
  if (impl_->scripts) return impl_->scripts->Presentation(foreground);
#endif
  return json::object();
}
void LinuxApp::StopScript() {
#if KELPIE_LINUX_HAS_CEF
  if (impl_->scripts) impl_->scripts->Stop();
#endif
}
}
