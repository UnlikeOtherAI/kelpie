#include "desktop_engine_impl.h"

namespace kelpie {

bool DesktopEngine::SendMouseClickEvent(int x, int y, int button, bool mouse_up, int click_count) {
  if (!impl_->browser || !impl_->browser->GetHost()) {
    return false;
  }
  cef_mouse_button_type_t button_type = MBT_LEFT;
  if (button == 2) {
    button_type = MBT_MIDDLE;
  } else if (button == 3) {
    button_type = MBT_RIGHT;
  }

  CefMouseEvent event;
  event.x = x;
  event.y = y;
  impl_->browser->GetHost()->SendMouseClickEvent(event, button_type, mouse_up, click_count);
  return true;
}

bool DesktopEngine::SendMouseWheelEvent(int x, int y, int delta_x, int delta_y) {
  if (!impl_->browser || !impl_->browser->GetHost()) {
    return false;
  }
  CefMouseEvent event;
  event.x = x;
  event.y = y;
  impl_->browser->GetHost()->SendMouseWheelEvent(event, delta_x, delta_y);
  return true;
}

void DesktopEngine::SetConsoleSink(JsonEventSink sink) {
  impl_->console_sink = std::move(sink);
}

void DesktopEngine::SetNetworkSink(JsonEventSink sink) {
  impl_->network_sink = std::move(sink);
}

CefRefPtr<DesktopDevToolsSession> DesktopEngine::Impl::NewDevToolsSession(CefRefPtr<CefBrowser> browser) {
  CefRefPtr<DesktopDevToolsSession> session = new DesktopDevToolsSession();
  // Forward through the engine so a sink installed later still receives events.
  session->Attach(browser, [this](const nlohmann::json& event) {
    if (network_sink) network_sink(event);
  });
  return session;
}

void DesktopEngine::SetNavigationSink(NavigationSink sink) {
  impl_->navigation_sink = std::move(sink);
}

CefRenderer& DesktopEngine::renderer() {
  return *renderer_;
}

const CefRenderer& DesktopEngine::renderer() const {
  return *renderer_;
}


}  // namespace kelpie
