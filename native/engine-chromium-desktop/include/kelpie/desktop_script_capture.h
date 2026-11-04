#pragma once
#include <memory>
#include <functional>
#include <string>
#include <nlohmann/json.hpp>
#include "kelpie/desktop_browser_control.h"
namespace kelpie {
// All encoder methods run on one capture worker; native UI delivery must be marshalled.
class DesktopScriptCapture {
 public:
  using Json = nlohmann::json;
  virtual ~DesktopScriptCapture() = default;
  virtual void AddFrame(const BrowserScreenshot& image, const Json& presentation,
                        double elapsed_ms, int action_index, bool step) = 0;
  virtual Json Finish(bool partial, const std::string& reason, double terminal_elapsed_ms) = 0;
};
using DesktopScriptCaptureFactory = std::function<std::unique_ptr<DesktopScriptCapture>(
    const nlohmann::json& options, const std::string& run_id, const std::string& owner)>;
}
