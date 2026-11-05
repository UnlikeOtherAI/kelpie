#include "desktop_script_runtime.h"
#include "kelpie/desktop_script_owner.h"
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/browser_schema.h"
#include "kelpie/native_extension_schema.h"
#include "kelpie/mcp_c_api.h"
#include "kelpie/response_helpers.h"
#include "desktop_input_planner.h"
#include "desktop_script_redaction.h"
#include <iomanip>
#include <set>
#include <algorithm>
#include <cmath>
#include <random>
#include <sstream>
#include <stdexcept>

namespace kelpie {
std::string NewDesktopScriptId() {
  std::random_device random;
  std::ostringstream text;
  for (int i = 0; i < 6; ++i) text << std::hex << std::setw(8) << std::setfill('0') << random();
  return text.str();
}
DesktopScriptHandler::DesktopScriptHandler(DesktopEngine& engine, DesktopRouter& router, Config config)
    : impl_(std::make_unique<Impl>(engine, router, std::move(config))) {}
DesktopScriptHandler::~DesktopScriptHandler() { RequestLocalAbort(); }
void DesktopScriptHandler::RequestLocalAbort() {
  std::lock_guard lock(impl_->mutex);
  if (impl_->running) impl_->abort->store(true);
}
void DesktopScriptHandler::NotifyNavigation() {
  TabLease lease; std::string document;
  {
    std::lock_guard lock(impl_->mutex);
    if(!impl_->running || !impl_->presentation.contains("tabId") || !impl_->presentation.contains("documentVersion")) return;
    lease.id=impl_->presentation.at("tabId"); lease.generation=impl_->presentation.at("generation");
    document=impl_->presentation.at("documentVersion");
  }
  BrowserNavigationState state;
  const auto result=impl_->engine.GetNavigationState(lease,&state,std::chrono::milliseconds(1));
  if(!result.ok || state.tab.document_version==document) return;
  {
    std::lock_guard lock(impl_->mutex);
    impl_->presentation.erase("marker"); impl_->presentation.erase("pointer"); impl_->presentation.erase("commentary");
    impl_->presentation_latched=false;
  }
  try { impl_->Present(); } catch(...) { RequestLocalAbort(); }
}
bool DesktopScriptHandler::IsRunning() const { std::lock_guard lock(impl_->mutex); return impl_->running; }
bool DesktopScriptHandler::Allows(std::string_view method) const {
  std::lock_guard lock(impl_->mutex);
  return !impl_->running || impl_->run_thread == std::this_thread::get_id() ||
      method == "get-script-status" || method == "abort-script" || method == "get-script-artifact" ||
      method == "close-browser" || method == "close-tab" || method == "get-device-info" || method == "get-dialog" || method == "handle-dialog";
}
void DesktopScriptHandler::Register() {
  impl_->router.Register("play-script", [this](const Json& body) { return impl_->Play(body); });
  impl_->router.Register("abort-script", [this](const Json& body) { return impl_->Abort(body); });
  impl_->router.Register("get-script-status", [this](const Json& body) { return impl_->Status(body); });
  impl_->router.Register("get-script-artifact", [this](const Json& body) {
    const auto owner = ScopedDesktopScriptOwner::Current();
    if (owner.empty() || !impl_->config.revalidate || !impl_->config.revalidate(owner) || !impl_->config.artifact) return ErrorResponse("SCRIPT_OWNER_REQUIRED", "Authenticated script owner is required");
    Json arguments=body;
    if(!ValidateBrowserJson(NativeExtensionInputSchema("get-script-artifact"),&arguments))
      return ErrorResponse("INVALID_PARAMS","Artifact request does not match the canonical schema");
    {
      std::lock_guard lock(impl_->mutex);
      if(impl_->running && owner==impl_->owner && arguments.value("runId",std::string())==impl_->run_id)
        return ErrorResponse("ARTIFACT_NOT_READY","Run artifacts become available after terminal privacy checks");
    }
    return impl_->config.artifact(arguments, owner);
  });
}
double DesktopScriptHandler::Impl::Elapsed() const {
  return std::chrono::duration<double, std::milli>(Clock::now() - began).count();
}
bool DesktopScriptHandler::Impl::Authorized(const Json& body) const {
  return !owner.empty() && config.revalidate && config.revalidate(owner) && ScopedDesktopScriptOwner::Current() == owner &&
      (!body.contains("runId") || (body["runId"].is_string() && body["runId"] == run_id));
}
DesktopScriptHandler::Json DesktopScriptHandler::Impl::Status(const Json& body) {
  std::lock_guard lock(mutex);
  if (!Authorized(body)) {
    if (!body.contains("runId"))
      return SuccessResponse({{"playing", false}, {"state", "idle"}, {"supportedVersions", Json::array({1})}});
    return ErrorResponse("SCRIPT_OWNER_REQUIRED", "Run owner is required");
  }
  Json result=SuccessResponse({{"playing",running},{"runId",run_id},
    {"supportedVersions",Json::array({1})},{"totalActions",status.value("totalActions",0)}});
  if(action_index>=0) result["actionIndex"]=action_index;
  if (running) {
    result["state"]=stop_sampler.load()?"finalizing":"running";
    result["elapsedMs"]=Elapsed(); result["abortRequested"]=abort->load();
    result["artifacts"]=Json::array();
  } else {
    const bool succeeded=terminal.value("success",false);
    const bool aborted=terminal.value("aborted",false);
    result["runSuccess"]=succeeded;
    result["state"]=aborted?"aborted":succeeded?"completed":"failed";
    for(const char* key:{"totalDurationMs","mayHaveCompleted","inputGuarantee","targetGuarantee","artifacts"})
      if(terminal.contains(key)) result[key]=terminal.at(key);
    if(!succeeded) {
      std::string code=aborted?"SCRIPT_ABORTED":"SCRIPT_FAILED";
      if(terminal.contains("error")) code=terminal["error"].value("code",code);
      if(code.empty() || code.size()>80 || code.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")!=std::string::npos)
        code="SCRIPT_FAILED";
      result["runError"]={{"code",code},{"message","Workflow did not complete successfully"}};
    }
  }
  // Query success is independent from historical run success. Project only the
  // public metadata schema so no authored action or terminal output can escape.
  return result;
}
DesktopScriptHandler::Json DesktopScriptHandler::Impl::Abort(const Json& body) {
  std::lock_guard lock(mutex);
  if (!Authorized(body)) return ErrorResponse("SCRIPT_OWNER_REQUIRED", "Run owner is required");
  if (!running) return ErrorResponse("NO_SCRIPT_RUNNING", "No script is playing");
  abort->store(true);
  changed.notify_all();
  return SuccessResponse({{"runId", run_id}, {"abortRequested", true}});
}
bool DesktopScriptHandler::Impl::Cancelled() const {
  if(!config.revalidate || !config.revalidate(owner)) {
    grant_revoked.store(true); abort->store(true); return true;
  }
  if (abort->load() || Clock::now() >= deadline) return true;
  std::lock_guard lock(mutex);
  return !capture_error.empty();
}
void DesktopScriptHandler::Impl::Pause(int milliseconds) {
  for (int remaining = milliseconds; remaining > 0; remaining -= 20) {
    if (Cancelled()) throw std::runtime_error("SCRIPT_STOPPED");
    std::this_thread::sleep_for(std::chrono::milliseconds(std::min(remaining, 20)));
  }
}
void DesktopScriptHandler::Impl::Present() {
  if (!config.present) return;
  Json copy; std::shared_ptr<std::atomic<bool>> cancellation;
  { std::lock_guard lock(mutex); if(presentation_latched) return; copy = presentation; copy["playing"] = running; copy["elapsedMs"]=Elapsed(); cancellation=abort; }
  config.present(copy, [this,cancellation] { cancellation->store(true); changed.notify_all(); });
}
DesktopScriptHandler::Json DesktopScriptHandler::Impl::Play(const Json& body) {
  const std::string admitted_owner = ScopedDesktopScriptOwner::Current();
  if (admitted_owner.empty()) return ErrorResponse("SCRIPT_OWNER_REQUIRED", "Authenticated transport owner is required");
  char* raw = kelpie_browser_validate_script(body.dump().c_str());
  if (!raw) return ErrorResponse("INVALID_SCRIPT", "Strict workflow preflight failed");
  Json validated = Json::parse(raw, nullptr, false);
  kelpie_mcp_free_string(raw);
  if (validated.is_discarded() || !validated.value("valid", false))
    return ErrorResponse("INVALID_SCRIPT", "Strict workflow preflight failed");
  const Json script = validated.at("script");
  if (script.contains("sessionId")) return ErrorResponse("SESSION_UNSUPPORTED", "This native script adapter does not accept external session IDs");
  const auto& actions = script.at("actions");
  bool sensitive = false, screenshot = false;
  std::set<std::string> output_names;
  std::vector<std::string> redactions;
  for (const auto& action : actions) {
    const std::string name = action.at("action");
    if (name == "fill" || name == "type") {
      if (!action.at("text").is_string()) return ErrorResponse("UNRESOLVED_INPUT", "Bind inputs before native admission");
      if (action.value("sensitive", false)) { sensitive = true; redactions.push_back(action.at("text")); }
    }
    if(name=="press-key") {
      const auto plan=desktop_input::PlanTrustedInput({{"type","key"},{"key",action.at("key")}},std::nullopt);
      if(!plan.ok) return ErrorResponse(plan.error_code,"Unsupported native key in workflow preflight");
    }
    screenshot = screenshot || name == "screenshot";
    if((name=="output" || name=="extract") && !output_names.insert(action.at("name").get<std::string>()).second)
      return ErrorResponse("DUPLICATE_OUTPUT","Named outputs must be unique");
  }
  if (sensitive && (script.contains("capture") || screenshot))
    return ErrorResponse("SENSITIVE_CAPTURE_REFUSED", "Secret-bearing workflows cannot capture media");
  if ((script.contains("capture") || screenshot) && (!config.capture || !config.discard)) return ErrorResponse("UNSUPPORTED", "Native capture is unavailable");
  const std::set<std::string> supported={"navigate","click","tap","fill","type","press-key","scroll","wait","wait-ready","assert","screenshot","commentary","output","extract"};
  for(const auto& action:actions) if(supported.count(action.at("action").get<std::string>())==0)
    return ErrorResponse("UNSUPPORTED_SCRIPT_ACTION","Workflow contains an action this native adapter does not implement");
  auto admission=config.admission?config.admission():nullptr;
  if(!admission) return ErrorResponse("BUSY","A prior browser operation still owns admission");
  if(!config.revalidate || !config.revalidate(admitted_owner)) return ErrorResponse("AUTHORIZATION_REVOKED","Local control grant is no longer active");
  {
    std::lock_guard lock(mutex);
    if (running) return ErrorResponse("BUSY", "A script owns the browser");
    running = true; action_index=-1; owner = admitted_owner; run_id = NewDesktopScriptId(); target_key = "__kelpie_script_" + run_id;
    run_thread = std::this_thread::get_id(); abort = std::make_shared<std::atomic<bool>>(false); stop_sampler.store(false);
    began = Clock::now(); deadline = began + std::chrono::milliseconds(300000);
    capture_error.clear(); artifacts = Json::array(); terminal = Json::object(); presentation = Json::object();
    sampler_ready = false; sampler_done = false; requested_step = completed_step = -1;
    requested_ticket=completed_ticket=0; requested_step_document.clear(); presentation_latched=false; grant_revoked.store(false); privacy_discard.store(false);
    status = {{"success", true}, {"playing", true}, {"runId", run_id}, {"totalActions", actions.size()}};
  }
  if(config.invalidate) config.invalidate();
  admission.reset();
  Json result = SuccessResponse({{"runId", run_id}, {"actionsExecuted", 0}});
  std::thread sampler;
  TabLease lease;
  try {
    auto resolved = engine.ResolveTab(script.at("tabId").get<std::string>(), std::nullopt, &lease, std::chrono::seconds(5));
    if (!resolved.ok) throw std::runtime_error("TAB_NOT_FOUND");
    lease.require_active = true; lease.cancelled = abort; lease.deadline = deadline;
    const bool auto_png=script.contains("capture") && std::any_of(script["capture"]["formats"].begin(),script["capture"]["formats"].end(),[](const Json& format){return format=="screenshots";});
    if (script.contains("capture") || screenshot) {
      Json options=script.value("capture",Json{{"formats",Json::array({"screenshots"})},{"fps",15},{"maxWidth",1280},{"maxBytes",67108864},{"maxDurationMs",60000}});
      if(screenshot && std::none_of(options["formats"].begin(),options["formats"].end(),[](const Json& format){return format=="screenshots";}))
        options["formats"].push_back("screenshots");
      sampler = std::thread([this, lease, options] { Sample(lease, options); });
      std::unique_lock lock(mutex);
      changed.wait_for(lock, std::chrono::seconds(10), [this] { return sampler_ready || sampler_done; });
      if (!sampler_ready || !capture_error.empty()) throw std::runtime_error("CAPTURE_SETUP_FAILED");
    }
    Json outputs = Json::object();
    for (std::size_t index = 0; index < actions.size(); ++index) {
      if (Cancelled()) throw std::runtime_error("SCRIPT_STOPPED");
      {
        std::lock_guard lock(mutex);
        action_index = static_cast<int>(index); status["currentAction"] = index;
        status["currentActionName"] = actions[index].at("action");
      }
      Json response = Perform(lease, actions[index], script, &outputs, &redactions);
      if(outputs.dump().size()>262144) {
        response=ErrorResponse("OUTPUT_BUDGET_EXCEEDED","Named outputs exceed the 256 KiB run budget");
        outputs=Json::object();
      }
      if (!response.value("success", false)) {
        result = response; result["actionsExecuted"] = index;
        break;
      }
      if (sampler.joinable() && !Cancelled()) {
        const std::string name=actions[index].at("action");
        const bool pointed=name=="click" || name=="tap" || name=="fill" || name=="type";
        StepScreenshot(static_cast<int>(index),(auto_png && !pointed) || name=="screenshot");
      }
      result["actionsExecuted"] = index + 1;
      if(index+1<actions.size()) Pause(script.value("defaultWaitBetweenActions", 0));
    }
    if(sampler.joinable() && !Cancelled() && result.value("success",false)) {
      double remaining=0;
      { std::lock_guard lock(mutex); if(presentation.contains("marker")) {
        const auto& marker=presentation["marker"];
        remaining=marker.value("startedMs",0.0)+marker.value("durationMs",700.0)-Elapsed();
      } }
      if(remaining>0) Pause(static_cast<int>(std::ceil(remaining)));
      // Admit a fully faded movie endpoint without exceeding configured FPS.
      Pause(static_cast<int>(std::ceil(1000.0/script.value("capture",Json::object()).value("fps",15))));
      StepScreenshot(action_index,false);
    }
    // Only explicitly requested terminal outputs are returned. Sensitive values never enter status.
    try { RedactScriptOutputs(outputs,actions,redactions); }
    catch(const std::exception& error) {
      const std::string code=std::string(error.what())=="OUTPUT_REDACTION_COLLISION"?"OUTPUT_REDACTION_COLLISION":"OUTPUT_REDACTION_LIMIT";
      privacy_discard.store(true);
      const bool uncertain=result.value("mayHaveCompleted",false);
      if(result.value("success",false)) result=ErrorResponse(code,"Named outputs could not be safely redacted");
      outputs=Json::object();
      if(uncertain) result["mayHaveCompleted"]=true;
    }
    result["outputs"] = std::move(outputs);
  } catch (...) {
    result = ErrorResponse("SCRIPT_STOPPED", "Script stopped before confirmed completion");
    result["mayHaveCompleted"] = true;
  }
  if(config.invalidate) config.invalidate();
  stop_sampler.store(true); changed.notify_all();
  if (sampler.joinable()) sampler.join();
  if(privacy_discard.load()) {
    try { if(config.discard) config.discard(run_id,owner); }
    catch(...) { capture_error="CAPTURE_PRIVACY_CLEANUP_FAILED"; }
    {std::lock_guard lock(mutex);artifacts=Json::array();}
  }
  if (!capture_error.empty()) {
    if(result.value("success",false) || result.value("error",Json::object()).value("code",std::string())=="SCRIPT_STOPPED") result=ErrorResponse(capture_error,"Capture ended at a native limit or failure");
    else result["captureError"]=capture_error;
  }
  if(grant_revoked.load()) result=ErrorResponse("AUTHORIZATION_REVOKED","Local control grant ended before completion");
  if (abort->load()) { result["success"] = false; result["aborted"] = true; }
  result["runId"] = run_id; result["totalDurationMs"] = Elapsed();
  result["inputGuarantee"] = "trusted-coordinate";
  result["targetGuarantee"] = "rechecked-before-dispatch-with-async-gap";
  const bool partial = !result.value("success", false);
  for (auto& artifact : artifacts) artifact["partial"] = partial;
  result["artifacts"] = artifacts;
  // Remove the one ephemeral identity token in the same isolated world.
  lease.cancelled.reset(); lease.deadline = Clock::now() + std::chrono::seconds(2);
  Json ignored;
  engine.EvaluateBrowserControl(lease, "delete globalThis[" + Json(target_key).dump() + "]", &ignored, std::chrono::seconds(2));
  { std::lock_guard lock(mutex); presentation = {{"playing", false}}; }
  try { if (config.present) config.present({{"playing", false}}, {}); }
  catch(...) {
    if(result.value("success",false)) result["error"]={{"code","CAPTURE_NATIVE_PRESENTATION_FAILED"},{"message","Native presentation cleanup failed"}};
    else result["captureError"]="CAPTURE_NATIVE_PRESENTATION_FAILED";
    result["success"]=false;
    for(auto& artifact:result["artifacts"]) artifact["partial"]=true;
  }
  {
    std::lock_guard lock(mutex);
    if(abort->load()) {
      result["success"]=false; result["aborted"]=true;
      for(auto& artifact:result["artifacts"]) artifact["partial"]=true;
    }
    terminal = result; terminal["playing"] = false; running = false; run_thread = {};
  }
  return result;
}
}
