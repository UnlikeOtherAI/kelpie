#pragma once
#include <atomic>
#include <functional>
#include <memory>
#include <nlohmann/json.hpp>
#include "kelpie/desktop_script_capture.h"
namespace kelpie {
class DesktopEngine;
class DesktopRouter;
class DesktopScriptHandler {
 public:
  using Json = nlohmann::json;
  struct Config {
    DesktopScriptCaptureFactory capture;
    std::function<std::shared_ptr<void>()> admission;
    std::function<void()> invalidate;
    std::function<bool(const std::string&)> revalidate;
    std::function<Json(const Json&, const std::string&)> artifact;
    std::function<void(const Json&, std::function<void()>)> present;
  };
  DesktopScriptHandler(DesktopEngine& engine, DesktopRouter& router, Config config);
  ~DesktopScriptHandler();
  void Register();
  void RequestLocalAbort();
  void NotifyNavigation();
  bool IsRunning() const;
  // Blocks unrelated legacy mutations while the run owns the browser.
  bool Allows(std::string_view method) const;
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
