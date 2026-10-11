#pragma once

#include <cstddef>
#include <iosfwd>
#include <functional>
#include <string_view>
#include <memory>
#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/platform.h"
#include "kelpie/desktop_browser_control.h"

namespace kelpie {

class DesktopRouter;
class McpRegistry;

class DesktopMcpServer {
 public:
  using json = nlohmann::json;

  struct Config {
    Platform platform = Platform::kLinux;
    std::string engine = "chromium";
    std::string server_name = "kelpie-desktop";
    std::string server_version = "0.0.1";
    std::istream* input = nullptr;
    std::ostream* output = nullptr;
    // Base64 budget for an authorized account `tab.screenshot`. Zero keeps the
    // capture unchanged; a limit retakes an oversized capture as JPEG and fails
    // SCREENSHOT_TOO_LARGE when no quality fits (see kelpie/screenshot_fit.h).
    std::size_t screenshot_base64_limit = 0;
  };

  DesktopMcpServer();
  ~DesktopMcpServer();

  void SetRouter(const DesktopRouter* router);
  void SetRegistry(const McpRegistry* registry);
  using FixedReader = std::function<json(const json&)>;
  using StepAuthorization = std::function<bool()>;
  void SetFixedReader(FixedReader reader);
  void SetPendingCheck(std::function<bool()> pending);
  void NotifyDocumentChanged() const;
  std::shared_ptr<void> GuardDispatch(std::string_view method, const json& params) const;
  void InvalidateReferences(std::string_view method, const json& params) const;
  json HandleBrowserRequest(const json& request, const Config& config) const;
  json HandleBrowserRequestAuthorized(const json& request, const Config& config,
                                      const StepAuthorization& authorize,
                                      const std::optional<TabLease>& job_lease = std::nullopt) const;

  bool Run(const Config& config);
  // Returns null for a valid JSON-RPC notification.  Stdio callers must not
  // write anything for that case; HTTP callers translate it to 202 with no body.
  json HandleRequest(const json& request, const Config& config) const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie
