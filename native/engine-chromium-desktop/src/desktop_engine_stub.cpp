#include "kelpie/desktop_engine.h"

namespace kelpie {

class DesktopEngine::Impl {
 public:
  explicit Impl(CefRenderer* renderer) : renderer_(renderer) {}

  bool Initialize(const Config& next_config) {
    config = next_config;
    viewport.width = config.viewport.width;
    viewport.height = config.viewport.height;
    viewport.offscreen = config.mode == Mode::kOffscreen;
    renderer_->SetCallbacks({});
    initialized = false;
    return false;
  }

  Config config;
  ViewportState viewport;
  CefRenderer* renderer_ = nullptr;
  bool initialized = false;
};

DesktopEngine::DesktopEngine()
    : impl_(nullptr),
      renderer_(std::make_unique<CefRenderer>()) {
  impl_ = std::make_unique<Impl>(renderer_.get());
}

DesktopEngine::~DesktopEngine() = default;

bool DesktopEngine::Initialize(const Config& config) {
  return impl_->Initialize(config);
}

void DesktopEngine::Shutdown() {}

void DesktopEngine::DoMessageLoopWork() {}

bool DesktopEngine::is_initialized() const {
  return false;
}

bool DesktopEngine::is_offscreen() const {
  return impl_->viewport.offscreen;
}

DesktopEngine::ViewportState DesktopEngine::viewport() const {
  return impl_->viewport;
}

bool DesktopEngine::ResizeViewport(int width, int height) {
  impl_->viewport.width = width;
  impl_->viewport.height = height;
  return true;
}

void DesktopEngine::SetConsoleSink(JsonEventSink) {}

void DesktopEngine::SetNetworkSink(JsonEventSink) {}

void DesktopEngine::SetNavigationSink(NavigationSink) {}

CefRenderer& DesktopEngine::renderer() {
  return *renderer_;
}

const CefRenderer& DesktopEngine::renderer() const {
  return *renderer_;
}

}  // namespace kelpie
