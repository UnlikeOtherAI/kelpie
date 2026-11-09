// Peer-to-peer cookie sync for the standalone Windows app: the shared
// desktop-sync service over the CEF global cookie store and Windows DNS-SD.
// Embedded (hosted) browsers never run it; they report it as embedded.
#include "windows_app.h"

#include "kelpie/desktop_sync_cookie_store.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {

// The service logs states and error codes only, never cookie data.
void LogCookieSync(const std::string& line) {
  OutputDebugStringA(("kelpie cookie sync: " + line + "\n").c_str());
}

// The published get-cookie-sync-status shape when no service runs here.
nlohmann::json CookieSyncNotRunning(const char* reason, bool signed_in) {
  return {{"supported", false}, {"reason", reason}, {"signedIn", signed_in}, {"listening", false},
          {"peers", nlohmann::json::array()},
          {"store", {{"entries", 0}, {"tombstones", 0}, {"localOnly", 0}, {"unapplied", 0}, {"skipped", 0},
                     {"warming", false}, {"lastPurgeAt", nullptr}}}};
}

}  // namespace

bool WindowsApp::IsStandalone() const {
  return !config_.hosted && config_.parent_window == nullptr && !config_.uoa_session;
}

// Called once the engine is initialised (the cookie store needs it) and
// before readiness is published, so no authorised status request can find
// a standalone app without its service.
void WindowsApp::StartCookieSync(const std::string& device_name) {
  if (!IsStandalone() || cookie_sync_ || !desktop_app_ || !account_) return;
  auto discovery = std::make_unique<SyncDiscoveryWindows>();
  auto cookies = CreateSyncCookieStore(desktop_app_->engine());
  DesktopCookieSync::Config sync;
  sync.profile_dir = utf::WideToUtf8(config_.profile_dir.wstring()).value_or(std::string());
  sync.platform = "windows";
  sync.device_name = device_name;
  sync.account = account_.get();
  sync.cookies = cookies.get();
  sync.discovery = discovery.get();
  sync.log = LogCookieSync;
  auto service = std::make_unique<DesktopCookieSync>(std::move(sync));
  std::lock_guard<std::mutex> lock(cookie_sync_mutex_);
  sync_discovery_ = std::move(discovery);
  sync_cookies_ = std::move(cookies);
  cookie_sync_ = std::move(service);
}

// UI thread only, like Start and Stop, so the pointer needs no lock here.
void WindowsApp::TickCookieSync() {
  if (cookie_sync_ && !close_lifecycle_.requested()) cookie_sync_->Tick();
}

// Before CEF shuts down: the service still reads the global cookie store, and
// the store must go before the engine does.
void WindowsApp::StopCookieSync() {
  std::unique_ptr<DesktopCookieSync> service;
  std::unique_ptr<SyncCookieStore> cookies;
  std::unique_ptr<SyncDiscoveryWindows> discovery;
  {
    std::lock_guard<std::mutex> lock(cookie_sync_mutex_);
    service = std::move(cookie_sync_);
    cookies = std::move(sync_cookies_);
    discovery = std::move(sync_discovery_);
  }
  if (service) service->Stop();
}

// get-cookie-sync-status, on an HTTP worker thread. Without a service the
// browser is embedded, or a standalone app is shutting down.
nlohmann::json WindowsApp::CookieSyncStatus() const {
  {
    std::lock_guard<std::mutex> lock(cookie_sync_mutex_);
    if (cookie_sync_) return cookie_sync_->Status();
  }
  const bool signed_in = account_ && account_->State().signed_in;
  return CookieSyncNotRunning(IsStandalone() ? "signed-out" : "embedded", signed_in);
}

}  // namespace kelpie::windows
