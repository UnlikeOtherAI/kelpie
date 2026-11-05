#include "linux_app_internal.h"

namespace kelpie::linuxapp {
bool LinuxApp::FocusBrowser(bool focused) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendFocusEvent(focused);
}

bool LinuxApp::SendBrowserMouseMove(int x, int y, bool mouse_leave) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendMouseMoveEvent(x, y, mouse_leave);
}

bool LinuxApp::SendBrowserMouseClick(int x, int y, int button, bool mouse_up, int click_count) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendMouseClickEvent(x, y, button, mouse_up, click_count);
}

bool LinuxApp::SendBrowserMouseWheel(int x, int y, int delta_x, int delta_y) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendMouseWheelEvent(x, y, delta_x, delta_y);
}

void LinuxApp::SetFullscreen(bool fullscreen) {
  impl_->desired_fullscreen.store(fullscreen);
}

bool LinuxApp::IsFullscreen() const {
  return impl_->current_fullscreen.load();
}

bool LinuxApp::WantsFullscreen() const {
  return impl_->desired_fullscreen.load();
}

void LinuxApp::ReportFullscreenState(bool fullscreen) {
  impl_->current_fullscreen.store(fullscreen);
  impl_->desired_fullscreen.store(fullscreen);
}

bool LinuxApp::HasNativeBrowser() const {
  return impl_->browser_initialized;
}

bool LinuxApp::ScreenshotSupported() const {
  return impl_->browser_initialized;
}

}  // namespace kelpie::linuxapp
