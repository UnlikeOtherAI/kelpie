// Trusted CDP script input. Target preflight and input are separate renderer commands;
// the unavoidable recheck-to-dispatch gap is reported, never described as atomic.
#include "desktop_engine_control_support.h"
#include "desktop_script_coordinates.h"
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"
#include <chrono>
#include <thread>
#include <algorithm>
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
    TabLease lease, const Json& options, const Json& action, Json* output, Timeout timeout,
    const std::function<bool()>& cancelled) {
  if(output) *output=Json::object();
  const auto began = std::chrono::steady_clock::now();
  bool dispatched = false, unclassified_mutation = false, native_pressed=false, native_keys=false;
  bool allow_non_input_privacy = false;
  struct CleanupOnExit {
    std::shared_ptr<Impl> impl; TabLease lease; bool& mouse; bool& keys;
    ~CleanupOnExit() { if(mouse || keys) QueueRelease(impl,lease); }
  } cleanup{impl_,lease,native_pressed,native_keys};
  Json target;
  const auto inspect = [&](bool privacy_only=false, bool prove_non_input=false) -> BrowserControlResult {
    const auto uncertain = [&]() { if (privacy_only && output) (*output)["inspectionUncertain"] = true; };
    if (cancelled && cancelled()) {
      uncertain();
      return BrowserControlResult::Failure("SCRIPT_STOPPED", "Script stopped");
    }
    // Drop only the document fence, retaining this tab ID, generation, active
    // requirement, cancellation and deadline. A closed/replaced tab is not a
    // navigation proof and never authorizes fallback.
    const auto same_tab_navigated = [&]() {
      if (!lease.document_version || lease.document_version->empty() || (cancelled && cancelled())) return false;
      TabLease same_tab = lease; same_tab.document_version.reset();
      BrowserNavigationState state;
      const auto remaining = std::min(RemainingTimeout(began, timeout),
        std::chrono::duration_cast<Timeout>(std::chrono::seconds(2)));
      if (remaining <= Timeout::zero()) return false;
      const auto observed = GetNavigationState(same_tab, &state, remaining);
      return observed.ok && !(cancelled && cancelled()) && !state.tab.document_version.empty() &&
        state.tab.document_version != *lease.document_version;
    };
    const auto unknown_privacy = [&](bool confirmed_navigation) {
      // Only the immediately acknowledged final click may consume this proof,
      // and only when this exact tab is independently known to have navigated.
      const bool allowed = confirmed_navigation && allow_non_input_privacy && output &&
        !output->value("sensitive", false) && !output->value("inspectionUncertain", false);
      allow_non_input_privacy = false;
      if (allowed) return BrowserControlResult::Success();
      uncertain();
      return options.value("policy", Json::object()).value("refuseSensitive", false)
        ? BrowserControlResult::Failure("TARGET_INSPECTION_INVALID", "Post-input privacy is unknown")
        : BrowserControlResult::Success();
    };
    const auto remaining = std::min(RemainingTimeout(began, timeout), std::chrono::duration_cast<Timeout>(std::chrono::seconds(10)));
    if (remaining <= Timeout::zero()) { uncertain(); return DeadlineExceeded(); }
    Json inspection_options = options;
    if (privacy_only) inspection_options["postMutation"] = true;
    if (prove_non_input) inspection_options["proveNonInput"] = true;
    char* raw = kelpie_browser_script_target_expression(inspection_options.dump().c_str());
    if (!raw) { uncertain(); return BrowserControlResult::Failure("INVALID_TARGET", "Shared target preflight rejected the request"); }
    Json generated;
    try { generated = Json::parse(raw); } catch (...) {
      kelpie_mcp_free_string(raw); uncertain();
      return BrowserControlResult::Failure("INVALID_TARGET", "Shared target expression is unavailable");
    }
    kelpie_mcp_free_string(raw);
    target=Json(); // A failed inspection cannot reuse an earlier classification.
    const auto read = EvaluateBrowserControl(lease, generated.at("expression").get<std::string>(), &target, remaining);
    if(output && target.is_object() && target.contains("sensitive") && target["sensitive"].is_boolean() && target["sensitive"].get<bool>()) (*output)["sensitive"]=true;
    if(output && !privacy_only && ScriptTargetInspectionUncertain(target)) (*output)["inspectionUncertain"]=true;
    if (cancelled && cancelled()) {
      uncertain();
      return BrowserControlResult::Failure("SCRIPT_STOPPED", "Script stopped");
    }
    if (!read.ok) {
      const bool navigated = privacy_only && read.error_code == "TAB_NOT_FOUND" && same_tab_navigated();
      if (cancelled && cancelled()) { uncertain(); return BrowserControlResult::Failure("SCRIPT_STOPPED", "Script stopped"); }
      if (navigated) return unknown_privacy(true);
      uncertain();
      return read;
    }
    if (!ScriptTargetInspectionExplicit(target)) {
      uncertain();
      return BrowserControlResult::Failure("TARGET_INSPECTION_INVALID","Fixed target inspection returned no usable result");
    }
    if (privacy_only) {
      if (!ScriptTargetPostMutationExplicit(target)) {
        uncertain();
        return BrowserControlResult::Failure("TARGET_INSPECTION_INVALID", "Post-input privacy classification is malformed");
      }
      if (!target["ok"].get<bool>()) {
        uncertain();
        return BrowserControlResult::Failure(ScriptTargetPostMutationErrorCode(target), "Post-input classification failed");
      }
      const bool known = target["sensitivityKnown"].get<bool>();
      if (!known) {
        const bool navigated = same_tab_navigated();
        if (cancelled && cancelled()) { uncertain(); return BrowserControlResult::Failure("SCRIPT_STOPPED", "Script stopped"); }
        return unknown_privacy(navigated);
      }
      if (target.value("sensitive", false) && options.value("policy", Json::object()).value("refuseSensitive", false))
        return BrowserControlResult::Failure("SENSITIVE_CAPTURE_REFUSED", "Sensitive input cannot expose captures");
      return BrowserControlResult::Success();
    }
    if (!target.value("ok", false))
      return BrowserControlResult::Failure(target.value("error", std::string("TARGET_FAILED")), "Target preflight refused input");
    if(ScriptTargetInspectionUncertain(target)) return BrowserControlResult::Failure("TARGET_INSPECTION_INVALID","Fixed target inspection returned no usable classification");
    return BrowserControlResult::Success();
  };
  const auto send = [&](const std::string& method, const Json& params) -> BrowserControlResult {
    if (cancelled && cancelled()) return BrowserControlResult::Failure("SCRIPT_STOPPED", "Script stopped");
    const auto remaining = std::min(RemainingTimeout(began, timeout), std::chrono::duration_cast<Timeout>(std::chrono::seconds(10)));
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    Json ignored;
    dispatched = true;
    unclassified_mutation = true;
    auto result=RunDevTools(impl_,lease,method,params,&ignored,remaining,[impl=impl_,lease,cancelled] {
      return IsDialogOpen(impl,lease) || (cancelled && cancelled());
    });
    if(result.error_code=="INTERRUPTED") {
      result=(cancelled && cancelled())
        ? BrowserControlResult::Failure("SCRIPT_STOPPED","Script stopped")
        : BrowserControlResult::Failure("DIALOG_OPENED","Native input opened a dialog");
      result.operation_may_have_completed=true;
    }
    return result;
  };
  const auto fail = [&](BrowserControlResult result) {
    if(native_pressed || native_keys) { QueueRelease(impl_,lease); native_pressed=false; native_keys=false; }
    result.operation_may_have_completed = result.operation_may_have_completed || dispatched;
    if (unclassified_mutation && output) (*output)["inspectionUncertain"] = true;
    return result;
  };
  auto result = inspect();
  if (!result.ok) return fail(result);
  const std::string type = action.value("action", std::string());
  const auto text_field = [](const Json& value, const char* key) {
    return value.contains(key) && value[key].is_string() ? value[key].get<std::string>() : std::string();
  };
  const std::string original_document = text_field(target, "documentId");
  const std::string original_token = options.value("token", std::string());
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
  const bool can_prove = type == "click" || type == "tap";
  result = inspect(false, can_prove);
  if (!result.ok) return fail(result);
  const bool non_input_proof = can_prove && !original_document.empty() && !original_token.empty() &&
    text_field(target, "documentId") == original_document &&
    text_field(target, "token") == original_token &&
    text_field(target, "sensitivityClass") == "non-input" &&
    target.contains("sensitive") && target["sensitive"].is_boolean() && !target["sensitive"].get<bool>() &&
    target.contains("sensitivityKnown") && target["sensitivityKnown"].is_boolean() && target["sensitivityKnown"].get<bool>() &&
    output && !output->value("sensitive", false) && !output->value("inspectionUncertain", false);
  Json released = mouse; released["type"] = "mouseReleased";
  const auto release = send("Input.dispatchMouseEvent", released);
  if (!release.ok) return fail(release);
  native_pressed=false;
  allow_non_input_privacy = non_input_proof;
  result = inspect(true);
  allow_non_input_privacy = false;
  if (!result.ok) return fail(result);
  unclassified_mutation = false;
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
    if (action.contains("_typingPlan")) {
      const auto& plan = action.at("_typingPlan");
      const auto& scalars = plan.at("scalars");
      const int delay = plan.at("typingDelayMs");
      // A clear can dispatch input even when there are no following scalars.
      if (type == "fill") {
        result = inspect(true);
        if (!result.ok) return fail(result);
        unclassified_mutation = false;
        if (output && output->value("inspectionUncertain", false) && !scalars.empty())
          return fail(BrowserControlResult::Failure("INPUT_UNCERTAIN", "Privacy is unknown before paced continuation"));
      }
      for (std::size_t index = 0; index < scalars.size(); ++index) {
        if (index) {
          const auto until = std::chrono::steady_clock::now() + std::chrono::milliseconds(delay);
          while (std::chrono::steady_clock::now() < until) {
            if (cancelled && cancelled()) return fail(BrowserControlResult::Failure("SCRIPT_STOPPED", "Script stopped"));
            if (RemainingTimeout(began, timeout) <= Timeout::zero()) return fail(DeadlineExceeded());
            const auto remaining = until - std::chrono::steady_clock::now();
            if (remaining > std::chrono::steady_clock::duration::zero())
              std::this_thread::sleep_for(std::min(remaining, std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::milliseconds(20))));
          }
        }
        result = inspect();
        if (!result.ok) return fail(result);
        if (!target.value("focused", false))
          return fail(BrowserControlResult::Failure("INPUT_UNCERTAIN", "Target lost focus before paced input"));
        result = send("Input.insertText", {{"text", scalars[index]}});
        if (!result.ok) return fail(result);
        result = inspect(true);
        if (!result.ok) return fail(result);
        unclassified_mutation = false;
        if (output && output->value("inspectionUncertain", false) && index + 1 < scalars.size())
          return fail(BrowserControlResult::Failure("INPUT_UNCERTAIN", "Privacy is unknown before paced continuation"));
      }
    } else {
      result = send("Input.insertText", {{"text", action.at("text")}});
      if (!result.ok) return fail(result);
      // The trusted input handler may change sensitivity before returning.
      result=inspect(true);
      if(!result.ok) return fail(result);
      unclassified_mutation = false;
    }
  }
  if (output) { const bool sensitive=output->value("sensitive",false), uncertain=output->value("inspectionUncertain",false); *output = {{"sensitive",sensitive},{"inspectionUncertain",uncertain},{"trusted", true}, {"inputGuarantee", "trusted-coordinate"},
                         {"targetGuarantee", "rechecked-before-dispatch-with-async-gap"}}; }
  return BrowserControlResult::Success();
}
}
