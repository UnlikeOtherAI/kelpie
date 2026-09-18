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

bool DesktopEngine::Shutdown() { return true; }

void DesktopEngine::DoMessageLoopWork() {}

const std::string& DesktopEngine::last_error() const {
  static const std::string error = "Chromium support is unavailable in this build";
  return error;
}

bool DesktopEngine::IsActiveNativeBrowserAttached(void*, Timeout) { return false; }

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

bool DesktopEngine::SendFocusEvent(bool focused) {
  (void)focused;
  return false;
}

bool DesktopEngine::SendMouseMoveEvent(int x, int y, bool mouse_leave) {
  (void)x;
  (void)y;
  (void)mouse_leave;
  return false;
}

bool DesktopEngine::SendMouseClickEvent(int x, int y, int button, bool mouse_up, int click_count) {
  (void)x;
  (void)y;
  (void)button;
  (void)mouse_up;
  (void)click_count;
  return false;
}

bool DesktopEngine::SendMouseWheelEvent(int x, int y, int delta_x, int delta_y) {
  (void)x;
  (void)y;
  (void)delta_x;
  (void)delta_y;
  return false;
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

namespace {

BrowserControlResult UnsupportedControl() {
  return BrowserControlResult::Failure("UNSUPPORTED", "Chromium desktop runtime is unavailable");
}

}  // namespace

BrowserControlResult DesktopEngine::GetTabs(std::vector<TabSnapshot>*, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::GetNavigationState(TabLease, NavigationState*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::ResolveTab(const std::optional<std::string>&,
                                               const std::optional<std::uint64_t>&,
                                               TabLease*,
                                               Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::CreateTab(const NewTabRequest&, TabSnapshot*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::GetPartitions(std::vector<PartitionInfo>*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::DeletePartition(const std::string&, PartitionDeletion*,
                                                    Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::ActivateTab(TabLease, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::CloseTab(TabLease, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::Navigate(std::optional<TabLease>, std::string, TabSnapshot*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::Back(TabLease, TabSnapshot*, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::Forward(TabLease, TabSnapshot*, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::Reload(TabLease, TabSnapshot*, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::StopLoading(TabLease, TabSnapshot*, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::Evaluate(TabLease, std::string, Json*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::Screenshot(TabLease, BrowserScreenshot*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::GetCookies(TabLease, const Json&, Json*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::SetCookies(TabLease, const Json&, Json*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::DeleteCookies(TabLease, const Json&, Json*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::DispatchTrustedInput(TabLease, const Json&, Json*, Timeout) {
  return UnsupportedControl();
}

// Session persistence is a browser-wide query, so the no-CEF configuration
// reports it unsupported rather than writing an empty snapshot over a real one.
BrowserControlResult DesktopEngine::GetSessionState(SessionState*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::GetDialog(TabLease, Json*, Timeout) { return UnsupportedControl(); }

BrowserControlResult DesktopEngine::HandleDialog(TabLease, const Json&, Json*, Timeout) {
  return UnsupportedControl();
}

BrowserControlResult DesktopEngine::DevTools(TabLease,
                                             std::string,
                                             const Json&,
                                             Json*,
                                             Timeout) {
  return UnsupportedControl();
}

}  // namespace kelpie
