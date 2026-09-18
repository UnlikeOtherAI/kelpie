#include "start_page_scheme.h"

#include <algorithm>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>

#include "include/cef_parser.h"
#include "include/cef_request.h"
#include "include/cef_resource_handler.h"
#include "include/cef_response.h"
#include "kelpie/start_page.h"

namespace kelpie {
namespace {

std::mutex supplier_mutex;
StartPageDataSupplier data_supplier;

std::string CurrentDataJson() {
  StartPageDataSupplier supplier;
  {
    std::lock_guard<std::mutex> lock(supplier_mutex);
    supplier = data_supplier;
  }
  if (!supplier) {
    return "{\"bookmarks\":[],\"recent\":[]}";
  }
  return supplier();
}

// Serves one in-memory body. The bytes are copied into the handler because the
// dynamic `data.json` payload is built per request and must outlive the call
// that produced it; the static assets are cheap enough that one copy per
// navigation is not worth a second code path.
class StartPageResourceHandler final : public CefResourceHandler {
 public:
  StartPageResourceHandler(std::string mime_type, std::string body)
      : mime_type_(std::move(mime_type)), body_(std::move(body)) {}

  bool Open(CefRefPtr<CefRequest>, bool& handle_request, CefRefPtr<CefCallback>) override {
    handle_request = true;
    return true;
  }

  void GetResponseHeaders(CefRefPtr<CefResponse> response,
                          int64_t& response_length,
                          CefString&) override {
    response->SetMimeType(mime_type_);
    response->SetStatus(200);
    // Same-origin only: nothing outside `kelpie://start` may read the user's
    // bookmarks or history, so no permissive CORS header is set.
    CefResponse::HeaderMap headers;
    headers.insert(std::make_pair("Cache-Control", "no-store"));
    headers.insert(std::make_pair("X-Content-Type-Options", "nosniff"));
    response->SetHeaderMap(headers);
    response_length = static_cast<int64_t>(body_.size());
  }

  bool Read(void* data_out,
            int bytes_to_read,
            int& bytes_read,
            CefRefPtr<CefResourceReadCallback>) override {
    bytes_read = 0;
    if (offset_ >= body_.size() || bytes_to_read <= 0) {
      return false;
    }
    const std::size_t remaining = body_.size() - offset_;
    const std::size_t count = std::min(remaining, static_cast<std::size_t>(bytes_to_read));
    std::memcpy(data_out, body_.data() + offset_, count);
    offset_ += count;
    bytes_read = static_cast<int>(count);
    return true;
  }

  void Cancel() override {}

 private:
  std::string mime_type_;
  std::string body_;
  std::size_t offset_ = 0;

  IMPLEMENT_REFCOUNTING(StartPageResourceHandler);
  DISALLOW_COPY_AND_ASSIGN(StartPageResourceHandler);
};

class StartPageSchemeHandlerFactory final : public CefSchemeHandlerFactory {
 public:
  CefRefPtr<CefResourceHandler> Create(CefRefPtr<CefBrowser>,
                                       CefRefPtr<CefFrame>,
                                       const CefString&,
                                       CefRefPtr<CefRequest> request) override {
    const std::string url = request->GetURL().ToString();
    if (start_page::IsDataRequest(url)) {
      return new StartPageResourceHandler("application/json; charset=utf-8", CurrentDataJson());
    }
    if (const start_page::Resource* resource = start_page::FindStaticResource(url)) {
      return new StartPageResourceHandler(std::string(resource->mime_type),
                                          std::string(resource->body));
    }
    // An unknown path under `kelpie://start` is a 404 rather than default
    // handling, which for a custom scheme would surface as a network error.
    return new StartPageResourceHandler("text/plain; charset=utf-8", "Not found");
  }

 private:
  IMPLEMENT_REFCOUNTING(StartPageSchemeHandlerFactory);
  DISALLOW_COPY_AND_ASSIGN(StartPageSchemeHandlerFactory);
};

}  // namespace

void RegisterKelpieCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) {
  if (registrar == nullptr) {
    return;
  }
  // STANDARD gives the scheme a real origin, which is what makes `start.js`'s
  // relative fetch of `data.json` a same-origin request. SECURE keeps the page
  // out of mixed-content downgrades. CORS_ENABLED and FETCH_ENABLED are what
  // allow the Fetch API to be used against the scheme at all. CSP bypassing is
  // deliberately *not* set: the page ships its own restrictive policy.
  registrar->AddCustomScheme(std::string(kInternalScheme),
                             CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE |
                                 CEF_SCHEME_OPTION_CORS_ENABLED |
                                 CEF_SCHEME_OPTION_FETCH_ENABLED);
}

bool RegisterStartPageSchemeHandler(StartPageDataSupplier supplier) {
  {
    std::lock_guard<std::mutex> lock(supplier_mutex);
    data_supplier = std::move(supplier);
  }
  return CefRegisterSchemeHandlerFactory(std::string(kInternalScheme), "start",
                                         new StartPageSchemeHandlerFactory());
}

}  // namespace kelpie
