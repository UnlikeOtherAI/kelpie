// Peer-to-peer cookie sync for the Chromium Linux app: the shared
// desktop-sync service over the CEF global cookie store and Avahi. The no-CEF
// fallback build does not sync.
#include "linux_desktop_internal.h"

#include <iostream>

#include "kelpie/desktop_sync_cookie_store.h"

namespace kelpie::linuxapp {

// Called once the engine is initialised (the cookie store needs it) and
// before readiness is published, so no authorised status request can find
// the app without its service.
void LinuxApp::Impl::StartCookieSync() {
  if (cookie_sync) return;
  auto discovery = std::make_unique<AvahiSyncDiscovery>();
  auto cookies = CreateSyncCookieStore(desktop.engine());
  DesktopCookieSync::Config sync;
  sync.profile_dir = config.profile_dir;
  sync.platform = "linux";
  sync.device_name = device.Collect().name;
  sync.account = &account;
  sync.cookies = cookies.get();
  sync.discovery = discovery.get();
  // States and error codes only, never cookie data.
  sync.log = [](const std::string& line) { std::cerr << "kelpie cookie sync: " << line << "\n"; };
  auto service = std::make_unique<DesktopCookieSync>(std::move(sync));
  std::lock_guard<std::mutex> lock(cookie_sync_mutex);
  sync_discovery = std::move(discovery);
  sync_cookies = std::move(cookies);
  cookie_sync = std::move(service);
}

// Before CEF shuts down: the service still reads the global cookie store, and
// the store must go before the engine does.
void LinuxApp::Impl::StopCookieSync() {
  std::unique_ptr<DesktopCookieSync> service;
  std::unique_ptr<SyncCookieStore> cookies;
  std::unique_ptr<AvahiSyncDiscovery> discovery;
  {
    std::lock_guard<std::mutex> lock(cookie_sync_mutex);
    service = std::move(cookie_sync);
    cookies = std::move(sync_cookies);
    discovery = std::move(sync_discovery);
  }
  if (service) service->Stop();
}

// get-cookie-sync-status, on an HTTP worker thread. Without a service the
// app is shutting down; the published shape still applies.
nlohmann::json LinuxApp::Impl::CookieSyncStatus() const {
  {
    std::lock_guard<std::mutex> lock(cookie_sync_mutex);
    if (cookie_sync) return cookie_sync->Status();
  }
  return {{"supported", false}, {"reason", "signed-out"}, {"signedIn", false}, {"listening", false},
          {"peers", nlohmann::json::array()},
          {"store", {{"entries", 0}, {"tombstones", 0}, {"localOnly", 0}, {"unapplied", 0}, {"skipped", 0},
                     {"warming", false}, {"lastPurgeAt", nullptr}}}};
}

}  // namespace kelpie::linuxapp
