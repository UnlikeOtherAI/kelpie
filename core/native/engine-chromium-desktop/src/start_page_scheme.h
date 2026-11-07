#pragma once

#include <functional>
#include <string>

#include "include/cef_scheme.h"

// CEF-only half of the start page: custom scheme registration and the resource
// handler that serves `kelpie://start`. The portable half — the resource table
// and the `data.json` builder — is in `include/kelpie/start_page.h` and compiles
// in both configurations.
namespace kelpie {

// Produces the `data.json` body. Called on the CEF IO thread, so the
// implementation must be thread-safe; the shared stores already are.
using StartPageDataSupplier = std::function<std::string()>;

// Declares `kelpie://` to Chromium. Must run from
// `CefApp::OnRegisterCustomSchemes` in every process, otherwise the renderer
// treats the scheme as unknown and the page cannot fetch its own payload.
void RegisterKelpieCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar);

// Installs the handler factory for `kelpie://start`. Must run after
// `CefInitialize`. Returns false when CEF rejects the registration.
bool RegisterStartPageSchemeHandler(StartPageDataSupplier supplier);

}  // namespace kelpie
