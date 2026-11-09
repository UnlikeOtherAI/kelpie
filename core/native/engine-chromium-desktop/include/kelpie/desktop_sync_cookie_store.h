#pragma once

#include <memory>

#include "kelpie/sync_cookie_store.h"

namespace kelpie {

class DesktopEngine;

// Cookie sync's view of the Chromium engine's default store: the global
// CefCookieManager (VisitAllCookies, SetCookie, and deletion as an
// already-expired SetCookie of the same key), with real HttpOnly, Secure,
// SameSite and expiry. Never a partition's store and no tab lease. The change
// signal fires after main-frame loads in unpartitioned tabs and every 15 s.
//
// Create after DesktopEngine::Initialize and destroy it, after stopping
// cookie sync, before DesktopEngine::Shutdown. Returns nullptr in builds
// without CEF.
std::unique_ptr<SyncCookieStore> CreateSyncCookieStore(DesktopEngine& engine);

}  // namespace kelpie
