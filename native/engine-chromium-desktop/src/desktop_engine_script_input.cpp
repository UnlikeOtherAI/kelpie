// Trusted CDP script input. Target preflight and input are separate renderer commands;
// the unavoidable recheck-to-dispatch gap is reported, never described as atomic.
#include "desktop_engine_control_support.h"
#include "desktop_script_coordinates.h"
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"
#include <chrono>
#include <optional>
#include "include/cef_task.h"
namespace {
class ReleaseScriptInput final : public CefTask {
 public:
  ReleaseScriptInput(std::shared_ptr<kelpie::DesktopEngine::Impl> impl,kelpie::TabLease lease)
      :impl_(std::move(impl)),lease_(std::move(lease)) {}
  void Execute() override {
    if(impl_->initialized && !impl_->shutting_down.load()) {
      // Cleanup only the same tab generation; never resolve a replacement tab or replay the action.
      lease_.cancelled.reset(); lease_.deadline.reset(); lease_.document_version.reset(); lease_.require_active=false;
      if(auto* tab=impl_->FindTab(lease_); tab && tab->browser && tab->browser->GetHost()) {
        CefMouseEvent mouse; mouse.x=-1; mouse.y=-1;
        tab->browser->GetHost()->SendMouseClickEvent(mouse,MBT_LEFT,true,1);
        for(int code:{17,65,8,35}) {
          CefKeyEvent key; key.type=KEYEVENT_KEYUP; key.windows_key_code=code; key.modifiers=0;
          tab->browser->GetHost()->SendKeyEvent(key);
        }
      }
    }
    impl_->script_input_cleanup.fetch_sub(1);
  }
 private:
  std::shared_ptr<kelpie::DesktopEngine::Impl> impl_; kelpie::TabLease lease_;
  IMPLEMENT_REFCOUNTING(ReleaseScriptInput);
};
void QueueRelease(const std::shared_ptr<kelpie::DesktopEngine::Impl>& impl,const kelpie::TabLease& lease) {
  impl->script_input_cleanup.fetch_add(1);
  if(!CefPostTask(TID_UI,new ReleaseScriptInput(impl,lease))) impl->script_input_cleanup.fetch_sub(1);
}
}

namespace kelpie {
using namespace engine_control;
BrowserControlResult DesktopEngine::DispatchScriptTarget(
    TabLease lease, const Json& options, const Json& action, Json* output, Timeout timeout) {
  if(output) *output=Json::object();
  const auto began = std::chrono::steady_clock::now();
  bool dispatched = false, native_pressed=false, native_keys=false;
  struct CleanupOnExit {
    std::shared_ptr<Impl> impl; TabLease lease; bool& mouse; bool& keys;
    ~CleanupOnExit() { if(mouse || keys) QueueRelease(impl,lease); }
  } cleanup{impl_,lease,native_pressed,native_keys};
  Json target;
  const auto inspect = [&](bool privacy_only=false) -> BrowserControlResult {
    const auto remaining = RemainingTimeout(began, timeout);
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    char* raw = kelpie_browser_script_target_expression(options.dump().c_str());
    if (!raw) return BrowserControlResult::Failure("INVALID_TARGET", "Shared target preflight rejected the request");
    Json generated;
    try { generated = Json::parse(raw); } catch (...) {
      kelpie_mcp_free_string(raw);
      return BrowserControlResult::Failure("INVALID_TARGET", "Shared target expression is unavailable");
    }
    kelpie_mcp_free_string(raw);
    target=Json(); // A failed inspection cannot reuse an earlier classification.
    const auto read = EvaluateBrowserControl(lease, generated.at("expression").get<std::string>(), &target, remaining);
    if(output && target.is_object() && target.value("sensitive",false)) (*output)["sensitive"]=true;
    if(output && ScriptTargetInspectionUncertain(target)) (*output)["inspectionUncertain"]=true;
    if (!read.ok) return read;
    if(!ScriptTargetInspectionExplicit(target)) return BrowserControlResult::Failure("TARGET_INSPECTION_INVALID","Fixed target inspection returned no usable result");
    if(privacy_only && !ScriptTargetInspectionUncertain(target)) {
      // Input already completed. A changed type/rectangle cannot undo it; this
      // final observation classifies privacy without repeating pre-input gates.
      if(target.value("sensitive",false) && options.value("policy",Json::object()).value("refuseSensitive",false))
        return BrowserControlResult::Failure(target.value("error",std::string("SENSITIVE_CAPTURE_REFUSED")),"Sensitive edit cannot expose captures");
      return BrowserControlResult::Success();
    }
    if (!target.value("ok", false))
      return BrowserControlResult::Failure(target.value("error", std::string("TARGET_FAILED")), "Target preflight refused input");
    if(ScriptTargetInspectionUncertain(target)) return BrowserControlResult::Failure("TARGET_INSPECTION_INVALID","Fixed target inspection returned no usable classification");
    return BrowserControlResult::Success();
  };
  const auto send = [&](const std::string& method, const Json& params) -> BrowserControlResult {
    const auto remaining = RemainingTimeout(began, timeout);
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    Json ignored;
    dispatched = true;
    auto result=RunDevTools(impl_,lease,method,params,&ignored,remaining,[impl=impl_,lease] { return IsDialogOpen(impl,lease); });
    if(result.error_code=="INTERRUPTED") {
      result=BrowserControlResult::Failure("DIALOG_OPENED","Native input opened a dialog");
      result.operation_may_have_completed=true;
    }
    return result;
  };
  const auto fail = [&](BrowserControlResult result) {
    if(native_pressed || native_keys) { QueueRelease(impl_,lease); native_pressed=false; native_keys=false; }
    result.operation_may_have_completed = result.operation_may_have_completed || dispatched;
    return result;
  };
  auto result = inspect();
  if (!result.ok) return fail(result);
  const std::string type = action.value("action", std::string());
  if ((type == "fill" || type == "type") && !target.value("editable", false))
    return BrowserControlResult::Failure("TARGET_NOT_EDITABLE", "Target is not an editable text control");
  const auto point=ScriptTargetCdpPoint(target);
  if(!point) return fail(BrowserControlResult::Failure("TARGET_VIEWPORT_UNAVAILABLE","Captured target viewport is unavailable"));
  const double x = point->x, y = point->y;
  const Json mouse = {{"x", x}, {"y", y}, {"button", "left"}, {"clickCount", 1}};
  Json pressed = mouse; pressed["type"] = "mousePressed";
  native_pressed=true;
  result = send("Input.dispatchMouseEvent", pressed);
  if (!result.ok) return fail(result);
  result = inspect();
  if (!result.ok) return fail(result);
  Json released = mouse; released["type"] = "mouseReleased";
  const auto release = send("Input.dispatchMouseEvent", released);
  if (!release.ok) return fail(release);
  native_pressed=false;
  if (type == "fill" || type == "type") {
    result = inspect();
    if (!result.ok) return fail(result);
    if(!target.value("focused",false)) return fail(BrowserControlResult::Failure("INPUT_UNCERTAIN","Target lost focus before text input"));
    if (type == "fill") {
      native_keys=true;
      const Json keys[] = {
        {{"type", "keyDown"}, {"key", "Control"}, {"code", "ControlLeft"}, {"windowsVirtualKeyCode", 17}, {"modifiers", 2}},
        {{"type", "keyDown"}, {"key", "a"}, {"code", "KeyA"}, {"windowsVirtualKeyCode", 65}, {"modifiers", 2}},
        {{"type", "keyUp"}, {"key", "a"}, {"code", "KeyA"}, {"windowsVirtualKeyCode", 65}, {"modifiers", 2}},
        {{"type", "keyUp"}, {"key", "Control"}, {"code", "ControlLeft"}, {"windowsVirtualKeyCode", 17}},
        {{"type", "keyDown"}, {"key", "Backspace"}, {"code", "Backspace"}, {"windowsVirtualKeyCode", 8}},
        {{"type", "keyUp"}, {"key", "Backspace"}, {"code", "Backspace"}, {"windowsVirtualKeyCode", 8}}
      };
      for (const auto& key : keys) {
        result = inspect();
        if (!result.ok) return fail(result);
        if(!target.value("focused",false)) return fail(BrowserControlResult::Failure("INPUT_UNCERTAIN","Target lost focus during text input"));
        result = send("Input.dispatchKeyEvent", key);
        if (!result.ok) return fail(result);
      }
    }
    result = inspect();
    if (!result.ok) return fail(result);
    if(!target.value("focused",false)) return fail(BrowserControlResult::Failure("INPUT_UNCERTAIN","Target lost focus before text insertion"));
    if(type=="type") {
      native_keys=true;
      for(const char* event:{"keyDown","keyUp"}) {
        result=inspect(); if(!result.ok) return fail(result);
        if(!target.value("focused",false)) return fail(BrowserControlResult::Failure("INPUT_UNCERTAIN","Target lost focus before text insertion"));
        result=send("Input.dispatchKeyEvent",{{"type",event},{"key","End"},{"code","End"},{"windowsVirtualKeyCode",35}});
        if(!result.ok) return fail(result);
      }
    }
    native_keys=false;
    result = send("Input.insertText", {{"text", action.at("text")}});
    if (!result.ok) return fail(result);
    // The trusted input handler may change sensitivity before returning.
    result=inspect(true);
    if(!result.ok) return fail(result);
  }
  if (output) { const bool sensitive=output->value("sensitive",false); *output = {{"sensitive",sensitive},{"trusted", true}, {"inputGuarantee", "trusted-coordinate"},
                         {"targetGuarantee", "rechecked-before-dispatch-with-async-gap"}}; }
  return BrowserControlResult::Success();
}
}
