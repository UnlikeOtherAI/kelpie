#pragma once

// The CefCookieManager backend for desktop_cookie_store. Works on any cookie
// manager: the global one (the default store) or a partition's
// CefRequestContext manager. Calls post to the CEF UI thread and wait, so
// they must never run on the UI thread itself.

#include "include/cef_cookie.h"
#include "desktop_cookie_store.h"

namespace kelpie {

class CefCookieBackend final : public desktop_cookie_store::CookieBackend {
 public:
  explicit CefCookieBackend(CefRefPtr<CefCookieManager> manager);

  bool VisitAll(Json* cookies, const desktop_cookie_store::Cancelled& cancelled) override;
  std::optional<std::vector<bool>> Apply(const std::vector<Write>& writes,
                                         const desktop_cookie_store::Cancelled& cancelled) override;

 private:
  using Json = desktop_cookie_store::Json;
  CefRefPtr<CefCookieManager> manager_;
};

// Conversions between CefCookie and the wire shape. A host-only cookie has an
// empty CefCookie domain; a domain cookie keeps its leading dot. Expiry is
// whole Unix seconds; `remove` produces an already-expired cookie with the
// same (domain, path, name), which deletes exactly that key.
nlohmann::json CefCookieToWire(const CefCookie& cookie);
CefCookie WireToCefCookie(const nlohmann::json& wire, bool remove, std::string* url);

}  // namespace kelpie
