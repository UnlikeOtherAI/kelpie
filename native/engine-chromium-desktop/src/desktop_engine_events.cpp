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
  event.modifiers = impl_->input_modifiers;
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
  event.modifiers = impl_->input_modifiers;
  impl_->browser->GetHost()->SendMouseWheelEvent(event, delta_x, delta_y);
  return true;
}

void DesktopEngine::SetConsoleSink(JsonEventSink sink) {
  impl_->console_sink = std::move(sink);
}

OffscreenFrame DesktopEngine::ViewFrame() const {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  auto result = impl_->frame;
  const auto& popup = impl_->popup;
  if (result.valid() && popup.valid() && result.tab_id == popup.tab_id && result.generation == popup.generation) {
    for (int y = 0; y < popup.height; ++y) for (int x = 0; x < popup.width; ++x) {
      const int dx = x + impl_->popup_rect.x, dy = y + impl_->popup_rect.y;
      if (dx < 0 || dy < 0 || dx >= result.width || dy >= result.height) continue;
      for (int c = 0; c < 4; ++c) result.pixels[(dy * result.width + dx) * 4 + c] = popup.pixels[(y * popup.width + x) * 4 + c];
    }
  }
  return result;
}
void DesktopEngine::SetInputModifiers(unsigned modifiers) { impl_->input_modifiers = modifiers; }
bool DesktopEngine::SendKeyEvent(int key, int native_key, unsigned modifiers, bool released) {
  if (!impl_->browser) return false;
  CefKeyEvent event;
  event.type = released ? KEYEVENT_KEYUP : KEYEVENT_RAWKEYDOWN;
  event.windows_key_code = key;
  event.native_key_code = native_key;
  event.modifiers = modifiers;
  impl_->browser->GetHost()->SendKeyEvent(event);
  return true;
}
bool DesktopEngine::CommitText(const std::string& text) {
  if (!impl_->browser) return false;
  impl_->browser->GetHost()->ImeCommitText(text, CefRange(UINT32_MAX, UINT32_MAX), 0);
  return true;
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
