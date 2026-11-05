#include "desktop_script_runtime.h"
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"
#include "kelpie/response_helpers.h"
#include <cmath>
#include "kelpie/script_presentation.h"
#include <algorithm>
#include <stdexcept>

namespace kelpie {
DesktopScriptHandler::Json DesktopScriptHandler::Impl::Target(
    TabLease lease, const Json& target, const std::string& token, bool observe) {
  Json options = {{"target", target}, {"key", target_key}, {"dispatch", false}, {"observe", observe}};
  if (!token.empty()) options["token"] = token;
  char* raw = kelpie_browser_script_target_expression(options.dump().c_str());
  if (!raw) return {{"ok", false}, {"error", "INVALID_TARGET"}};
  Json generated = Json::parse(raw, nullptr, false);
  kelpie_mcp_free_string(raw);
  if (generated.is_discarded() || !generated.contains("expression")) return {{"ok", false}, {"error", "INVALID_TARGET"}};
  Json value;
  const auto result = engine.EvaluateBrowserControl(lease, generated.at("expression"), &value, std::chrono::seconds(5));
  return result.ok ? value : Json{{"ok", false}, {"error", result.error_code}, {"mayHaveCompleted", result.operation_may_have_completed}};
}
DesktopScriptHandler::Json DesktopScriptHandler::Impl::Perform(
    TabLease lease, const Json& action, const Json& script, Json* outputs, std::vector<std::string>* redactions) {
  const std::string name = action.at("action");
  ScopedBrowserControlLease owned(lease);
  const auto failed_target = [](const Json& target) {
    Json result = ErrorResponse(target.value("error", std::string("TARGET_FAILED")), "Target operation refused before confirmed completion");
    result["mayHaveCompleted"] = target.value("mayHaveCompleted", false);
    return result;
  };
  if (name == "click" || name == "tap" || name == "fill" || name == "type") {
    auto resolved = Target(lease, action.at("target"));
    if (!resolved.value("ok", false)) return failed_target(resolved);
    if (resolved.value("sensitive", false) && (script.contains("capture") ||
        std::any_of(script["actions"].begin(), script["actions"].end(), [](const Json& item) { return item["action"] == "screenshot"; })))
      return ErrorResponse("SENSITIVE_CAPTURE_REFUSED", "Sensitive controls cannot be edited while capturing");
    if(resolved.value("sensitive",false) && (name=="fill" || name=="type")) redactions->push_back(action.at("text"));
    BrowserNavigationState navigation;
    const auto observed = engine.GetNavigationState(lease, &navigation, std::chrono::seconds(2));
    if (!observed.ok) return ErrorResponse(observed.error_code, "Owned document is unavailable");
    const double x = resolved.at("x"), y = resolved.at("y");
    Json pointer = script.value("pointer", Json::object());
    const double duration = pointer.value("enabled", false) ? pointer.value("durationMs", 500) : 0;
    double start_x = std::max(0.0, x - 100), start_y = std::max(0.0, y - 70);
    {
      std::lock_guard lock(mutex);
      if (presentation.contains("pointer")) {
        start_x = presentation["pointer"].value("x", start_x); start_y = presentation["pointer"].value("y", start_y);
      }
      presentation["tabId"]=lease.id; presentation["generation"]=lease.generation;
      presentation["documentVersion"] = navigation.tab.document_version;
      presentation["viewportWidth"] = resolved.at("viewportWidth"); presentation["viewportHeight"] = resolved.at("viewportHeight");
    }
    const double moved_at = Elapsed();
    do {
      if (Cancelled()) throw std::runtime_error("SCRIPT_STOPPED");
      const double progress=kelpie_script_progress(Elapsed()-moved_at,duration);
      const auto position=kelpie_script_pointer_position({start_x,start_y},{x,y},pointer.value("curve",std::string("s"))=="s",progress);
      const double px=position.x, py=position.y;
      if (pointer.value("enabled", false)) {
        { std::lock_guard lock(mutex); presentation["pointer"] = {{"x", px}, {"y", py}}; presentation["elapsedMs"] = Elapsed(); }
        Present();
      }
      if (progress >= 1) break;
      Pause(16);
    } while (true);
    resolved = Target(lease, action.at("target"), resolved.at("token"));
    if (!resolved.value("ok", false)) return failed_target(resolved);
    bool sampling=false;
    {
      std::lock_guard lock(mutex);
      sampling=sampler_ready && !sampler_done;
      presentation["marker"] = script.value("tapIndicator", Json::object());
      presentation["marker"]["x"] = x; presentation["marker"]["y"] = y;
      presentation["marker"]["actionIndex"]=action_index;
      // A future planned start clamps progress to zero until capture supplies
      // real encoded evidence. It cannot expire before the 300s run deadline.
      presentation["marker"]["startedMs"] = Elapsed()+(sampling?300001.0:0.0);
      presentation["elapsedMs"] = Elapsed();
    }
    Present();
    if(sampling) {
      const bool png=script.contains("capture") && std::any_of(script["capture"]["formats"].begin(),script["capture"]["formats"].end(),[](const Json& format){return format=="screenshots";});
      StepScreenshot(action_index,png,navigation.tab.document_version);
      {
        std::lock_guard lock(mutex);
        if(presentation.contains("marker")) presentation["marker"]["startedMs"]=Elapsed();
      }
      Present();
    }
    if(Cancelled()) throw std::runtime_error("SCRIPT_STOPPED");
    Json options = {{"target", action.at("target")}, {"key", target_key}, {"token", resolved.at("token")}, {"dispatch", false}};
    Json output;
    lease.document_version = navigation.tab.document_version;
    const auto result = engine.DispatchScriptTarget(lease, options, action, &output, std::chrono::seconds(10));
    if(config.invalidate) config.invalidate();
    if (!result.ok) {
      { std::lock_guard lock(mutex); presentation.erase("marker"); }
      Present();
      Json failure = ErrorResponse(result.error_code, "Native target input did not complete with a confirmed result");
      failure["mayHaveCompleted"] = result.operation_may_have_completed;
      return failure;
    }
    return SuccessResponse({{"inputGuarantee", "trusted-coordinate"}});
  }
  if (name == "wait") { Pause(action.at("ms")); return SuccessResponse(); }
  if (name == "screenshot") return SuccessResponse();
  if (name == "extract") {
    const Json response=router.Dispatch("browser-control",{{"version",1},{"method","tab.extract"},{"tabId",lease.id},{"params",action.at("params")}}).body;
    if(!response.value("ok",false)) return ErrorResponse("EXTRACT_FAILED","Structured extraction did not complete");
    if(!response.contains("value")) return ErrorResponse("EXTRACT_INVALID_RESULT","Structured extraction returned no value");
    (*outputs)[action.at("name").get<std::string>()]=response.at("value");
    return SuccessResponse();
  }
  if (name == "output") {
    const std::string source = action.at("source");
    const std::string field = source == "url" ? "location.href" : source == "title" ? "document.title" : "document.readyState";
    const std::string expression="(function(){var value="+field+";if(value.length>16384)return{tooLarge:true};return{value:value};})()";
    Json value;
    const auto result = engine.EvaluateBrowserControl(lease, expression, &value, std::chrono::seconds(2));
    if (!result.ok) return ErrorResponse(result.error_code, "Output observation failed");
    if(value.value("tooLarge",false)) return ErrorResponse("OUTPUT_VALUE_TOO_LARGE","Requested output exceeds the native value limit");
    (*outputs)[action.at("name").get<std::string>()] = value.at("value");
    return SuccessResponse();
  }
  if (name == "assert" || name == "wait-ready") {
    const auto started = Clock::now();
    const int timeout = action.value("timeoutMs", 10000);
    do {
      if (Cancelled()) throw std::runtime_error("SCRIPT_STOPPED");
      if (name == "assert") {
        const auto target = Target(lease, action.at("target"), "", true);
        const std::string desired = action.at("state");
        const bool visible = target.value("ok", false), hidden = target.value("error", std::string()) == "TARGET_NOT_FOUND";
        if ((desired == "hidden" && hidden) || (desired == "visible" && visible) ||
            (desired == "enabled" && visible && target.value("enabled", false))) return SuccessResponse();
        if (!visible && !hidden) return failed_target(target);
      } else {
        Json params={{"state",action.value("state",std::string("interactive"))}};
        if(action.contains("selector")) params["selector"]=action.at("selector");
        const auto observed=router.Dispatch("browser-control",{{"version",1},{"method","tab.ready"},
          {"tabId",lease.id},{"params",params}}).body;
        if(!observed.value("ok",false)) return ErrorResponse("READINESS_FAILED","Canonical readiness observation failed");
        if(observed.at("value").value("ready",false)) return SuccessResponse();
      }
      if (Clock::now() - started >= std::chrono::milliseconds(timeout)) break;
      Pause(50);
    } while (true);
    return ErrorResponse("TIMEOUT", "Requested observation state was not reached");
  }
  if (name == "commentary") {
    // Native presentation also appears in composited captures; no page DOM injection.
    { std::lock_guard lock(mutex); presentation["commentary"] = action; presentation["commentary"]["startedMs"] = Elapsed(); }
    Present();
    return SuccessResponse();
  }
  if (name == "navigate" || name == "scroll" || name == "press-key") {
    { std::lock_guard lock(mutex); presentation.erase("marker"); presentation.erase("pointer"); }
    Present();
    Json params = action; params.erase("action"); params["tabId"] = lease.id;
    const Json response=router.Dispatch(name,params).body;
    if(response.contains("input") && response["input"].value("dialogOpened",false)) {
      Json stopped=ErrorResponse("DIALOG_OPENED","Native input opened a dialog; handle it before another script");
      stopped["mayHaveCompleted"]=true; return stopped;
    }
    return response;
  }
  return ErrorResponse("UNSUPPORTED_SCRIPT_ACTION", "Native script action is unavailable");
}
}
