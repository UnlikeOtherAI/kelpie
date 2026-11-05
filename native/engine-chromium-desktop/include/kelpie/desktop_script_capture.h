#pragma once
#include <memory>
#include <functional>
#include <string>
#include <nlohmann/json.hpp>
#include "kelpie/desktop_browser_control.h"
namespace kelpie {
// A marker is acknowledged only after every requested movie encoder commits its frame.
// PNG-only/no-movie adapters return the default and never fabricate movie evidence.
enum class DesktopScriptFramePurpose { Ordinary, TerminalClear };
struct DesktopScriptFrameAdmission {
  int committed_marker_action=-1;
  std::string committed_marker_document;
};
// All encoder methods run on one capture worker; native UI delivery must be marshalled.
class DesktopScriptCapture {
 public:
  using Json = nlohmann::json;
  virtual ~DesktopScriptCapture() = default;
  virtual bool SupportsTerminalClear() const { return false; }
  virtual DesktopScriptFrameAdmission AddFrame(const BrowserScreenshot& image, const Json& presentation,
                        double elapsed_ms, int action_index, bool step, DesktopScriptFramePurpose purpose) = 0;
  virtual Json Finish(bool partial, const std::string& reason, double terminal_elapsed_ms) = 0;
};
using DesktopScriptCaptureFactory = std::function<std::unique_ptr<DesktopScriptCapture>(
    const nlohmann::json& options, const std::string& run_id, const std::string& owner)>;
}
