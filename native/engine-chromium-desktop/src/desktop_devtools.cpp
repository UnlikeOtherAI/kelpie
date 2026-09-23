#include "desktop_devtools.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <ctime>
#include <iomanip>
#include <limits>
#include <sstream>
#include <utility>
#include <vector>

#include "include/cef_task.h"
#include "include/cef_values.h"

namespace kelpie {
namespace {

DesktopDevToolsSession::Result Failure(std::string code, std::string message, bool may_have_completed = false) {
  return {false, std::move(code), std::move(message), nlohmann::json::object(), may_have_completed};
}

int ModifierMask(const nlohmann::json& input) {
  int mask = 0;
  for (const auto& item : input.value("modifiers", nlohmann::json::array())) {
    if (!item.is_string()) continue;
    if (item == "Alt") mask |= 1;
    if (item == "Control") mask |= 2;
    if (item == "Meta") mask |= 4;
    if (item == "Shift") mask |= 8;
  }
  return mask;
}

std::optional<std::string> StringMember(const nlohmann::json& object, const char* key) {
  const auto value = object.find(key);
  if (value == object.end() || !value->is_string()) return std::nullopt;
  return value->get<std::string>();
}

double NumberMember(const nlohmann::json& object, const char* key, double fallback = 0) {
  const auto value = object.find(key);
  return value != object.end() && value->is_number() ? value->get<double>() : fallback;
}

std::string IsoUtc(double seconds) {
  if (!std::isfinite(seconds)) {
    seconds = std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();
  }
  std::time_t whole = static_cast<std::time_t>(std::floor(seconds));
  int millis = static_cast<int>(std::llround((seconds - std::floor(seconds)) * 1000));
  if (millis == 1000) { ++whole; millis = 0; }
  std::tm utc{};
#if defined(_WIN32)
  if (gmtime_s(&utc, &whole) != 0) return "";
#else
  if (!gmtime_r(&whole, &utc)) return "";
#endif
  char buffer[32] = {};
  if (std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%S", &utc) == 0) return "";
  std::ostringstream output;
  output << buffer << '.' << std::setw(3) << std::setfill('0') << millis << 'Z';
  return output.str();
}

}  // namespace

std::optional<DesktopNetworkEventAdapter::Json> DesktopNetworkEventAdapter::Observe(
    const std::string& method, const Json& params) {
  if (!params.is_object()) return std::nullopt;
  const auto request_id = StringMember(params, "requestId");
  if (!request_id || request_id->empty()) return std::nullopt;

  if (method == "Network.requestWillBeSent") {
    const auto request = params.find("request");
    if (request == params.end() || !request->is_object()) return std::nullopt;
    const auto url = StringMember(*request, "url");
    if (!url || url->empty()) return std::nullopt;
    if (requests_.size() >= kMaxPendingRequests && requests_.find(*request_id) == requests_.end()) {
      requests_.erase(requests_.begin());
    }
    Request state;
    state.url = *url;
    state.method = StringMember(*request, "method").value_or("GET");
    state.type = StringMember(params, "type").value_or("Other");
    state.started_at = NumberMember(params, "timestamp");
    state.timestamp = IsoUtc(NumberMember(params, "wallTime", std::numeric_limits<double>::quiet_NaN()));
    const auto initiator = params.find("initiator");
    if (initiator != params.end() && initiator->is_object()) {
      const auto type = StringMember(*initiator, "type");
      if (type && *type == "script") state.initiator = "js";
    }
    requests_[*request_id] = std::move(state);
    return std::nullopt;
  }

  const auto pending = requests_.find(*request_id);
  if (pending == requests_.end()) return std::nullopt;
  if (method == "Network.responseReceived") {
    const auto response = params.find("response");
    if (response == params.end() || !response->is_object()) return std::nullopt;
    if (const auto status = response->find("status"); status != response->end() && status->is_number()) {
      pending->second.status = static_cast<int>(status->get<double>());
    }
    pending->second.content_type = StringMember(*response, "mimeType").value_or("");
    pending->second.type = StringMember(params, "type").value_or(pending->second.type);
    return std::nullopt;
  }

  const bool finished = method == "Network.loadingFinished";
  const bool failed = method == "Network.loadingFailed";
  if (!finished && !failed) return std::nullopt;
  Request state = std::move(pending->second);
  requests_.erase(pending);
  const double completed_at = NumberMember(params, "timestamp", state.started_at);
  const auto duration = static_cast<int>(std::clamp(
      std::llround(std::max(0.0, completed_at - state.started_at) * 1000.0), 0LL,
      static_cast<long long>(std::numeric_limits<int>::max())));
  Json event = {
      {"id", *request_id}, {"method", state.method}, {"url", state.url},
      {"status", state.status}, {"contentType", state.content_type}, {"type", state.type},
      {"duration", duration}, {"size", 0}, {"initiator", state.initiator}, {"timestamp", state.timestamp},
  };
  if (finished) {
    const auto bytes = params.find("encodedDataLength");
    if (bytes != params.end() && bytes->is_number()) {
      event["size"] = static_cast<long long>(std::max(0.0, bytes->get<double>()));
    }
  } else {
    event["failure"] = StringMember(params, "errorText").value_or("Network request failed");
  }
  return event;
}

void DesktopNetworkEventAdapter::Clear() { requests_.clear(); }

DesktopDevToolsSession::DesktopDevToolsSession() = default;
DesktopDevToolsSession::~DesktopDevToolsSession() { CancelAll(); }

void DesktopDevToolsSession::Attach(CefRefPtr<CefBrowser> browser, NetworkEventSink network_sink) {
  if (!browser || !CefCurrentlyOn(TID_UI)) return;
  CefRefPtr<CefBrowserHost> host = browser->GetHost();
  if (!host) return;
  int enable_id = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (browser_ && !browser_->IsSame(browser)) return;
    browser_ = browser;
    network_sink_ = std::move(network_sink);
    if (!registration_) registration_ = host->AddDevToolsMessageObserver(this);
    if (!registration_) return;
    enable_id = next_message_id_++;
  }
  host->ExecuteDevToolsMethod(enable_id, "Network.enable", CefDictionaryValue::Create());
}

std::shared_ptr<DesktopDevToolsSession::Operation> DesktopDevToolsSession::Begin(
    CefRefPtr<CefBrowser> browser, const std::string& method, const Json& params) {
  int message_id = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    message_id = next_message_id_++;
  }
  auto operation = std::shared_ptr<Operation>(new Operation(message_id));
  if (!browser || method.empty() || !CefCurrentlyOn(TID_UI)) {
    Complete(operation, Failure("INTERNAL", "DevTools methods must begin on the CEF UI thread"));
    return operation;
  }
  CefRefPtr<CefBrowserHost> host = browser->GetHost();
  if (!host) {
    Complete(operation, Failure("TAB_NOT_FOUND", "The tab has no CEF browser host"));
    return operation;
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (browser_ && !browser_->IsSame(browser)) {
      Complete(operation, Failure("INTERNAL", "A DevTools session may only serve its owning tab"));
      return operation;
    }
    browser_ = browser;
    if (!registration_) registration_ = host->AddDevToolsMessageObserver(this);
    if (!registration_) {
      Complete(operation, Failure("INTERNAL", "CEF did not register the DevTools observer"));
      return operation;
    }
    pending_.emplace(message_id, operation);
  }
  if (host->ExecuteDevToolsMethod(message_id, method, ToCefDictionary(params)) == 0) {
    std::lock_guard<std::mutex> lock(mutex_);
    pending_.erase(message_id);
    Complete(operation, Failure("DEVTOOLS_REJECTED", "CEF rejected the DevTools method"));
  }
  return operation;
}

DesktopDevToolsSession::Result DesktopDevToolsSession::Wait(const std::shared_ptr<Operation>& operation,
                                                             std::chrono::milliseconds timeout) {
  if (!operation) return Failure("INTERNAL", "DevTools operation is required");
  if (CefCurrentlyOn(TID_UI)) return Failure("INTERNAL", "Waiting for DevTools on the CEF UI thread is forbidden");
  std::unique_lock<std::mutex> lock(operation->mutex_);
  if (operation->completed_.wait_for(lock, timeout, [&] { return operation->done_; })) return operation->result_;
  operation->abandoned_ = true;
  lock.unlock();
  std::lock_guard<std::mutex> pending_lock(mutex_);
  const auto it = pending_.find(operation->message_id_);
  if (it != pending_.end() && it->second == operation) pending_.erase(it);
  return Failure("TIMEOUT", "DevTools operation timed out", true);
}

void DesktopDevToolsSession::CancelAll() {
  std::vector<std::shared_ptr<Operation>> operations;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (const auto& [_, operation] : pending_) operations.push_back(operation);
    pending_.clear();
    registration_ = nullptr;
    browser_ = nullptr;
    network_events_.Clear();
    network_sink_ = nullptr;
  }
  for (const auto& operation : operations) Complete(operation, Failure("CANCELLED", "Tab closed or browser shut down"));
}

DesktopDevToolsSession::Json DesktopDevToolsSession::EvaluateParams(const std::string& expression) {
  const std::string source = Json(expression).dump();
  const std::string wrapper =
      "(async()=>{const __kelpieSource=" + source + ";"
      "const __kelpieEnvelope=(kind,extra)=>Object.assign({__kelpieRuntimeEnvelope:1,kind:kind},extra||{});"
      "try{const value=await (0,eval)(__kelpieSource);"
      "if(value===undefined)return __kelpieEnvelope('undefined');"
      "if(typeof value==='bigint')return __kelpieEnvelope('bigint',{value:value.toString()});"
      "if(typeof value==='number'&&!Number.isFinite(value))return __kelpieEnvelope('nonfinite',{value:String(value)});"
      "if(typeof Node!=='undefined'&&value instanceof Node)return __kelpieEnvelope('node',{nodeName:value.nodeName,nodeType:value.nodeType});"
      "if(typeof value==='function'||typeof value==='symbol')return __kelpieEnvelope('non_json',{valueType:typeof value,description:String(value)});"
      "try{const encoded=JSON.stringify(value);if(encoded===undefined)return __kelpieEnvelope('non_json',{valueType:typeof value});"
      "return __kelpieEnvelope('json',{value:JSON.parse(encoded)});}catch(error){return __kelpieEnvelope(/circular/i.test(String(error))?'cyclic':'non_json',{description:String(error)});}}"
      "catch(error){return __kelpieEnvelope('exception',{name:String(error&&error.name||'Error'),message:String(error&&error.message||error),stack:String(error&&error.stack||'')});}})()";
  return {{"expression", wrapper}, {"awaitPromise", true}, {"returnByValue", true}, {"userGesture", true}};
}

DesktopDevToolsSession::Result DesktopDevToolsSession::ParseEvaluateResult(const Result& protocol_result) {
  if (!protocol_result.ok) return protocol_result;
  if (!protocol_result.value.is_object()) return Failure("CDP_MALFORMED_RESULT", "Runtime.evaluate did not return an object");
  if (protocol_result.value.contains("exceptionDetails")) {
    const auto& details = protocol_result.value["exceptionDetails"];
    return Failure("JAVASCRIPT_ERROR", details.is_object() && details.contains("text") && details["text"].is_string()
        ? details["text"].get<std::string>() : "JavaScript evaluation failed");
  }
  const auto remote_it = protocol_result.value.find("result");
  if (remote_it == protocol_result.value.end() || !remote_it->is_object()) {
    return Failure("CDP_MALFORMED_RESULT", "Runtime.evaluate did not return a remote object");
  }
  const auto& remote = *remote_it;
  if (!remote.contains("value") || !remote["value"].is_object()) {
    return Failure("CDP_MALFORMED_RESULT", "Runtime.evaluate did not return the Kelpie result envelope");
  }
  const auto& envelope = remote["value"];
  const auto marker = envelope.find("__kelpieRuntimeEnvelope");
  const auto kind_value = envelope.find("kind");
  if (marker == envelope.end() || !marker->is_number_integer() || marker->get<int>() != 1 ||
      kind_value == envelope.end() || !kind_value->is_string()) {
    return Failure("CDP_MALFORMED_RESULT", "Runtime.evaluate returned an invalid Kelpie result envelope");
  }
  const std::string kind = kind_value->get<std::string>();
  if (kind == "exception") {
    const auto message = envelope.find("message");
    return Failure("JAVASCRIPT_ERROR", message != envelope.end() && message->is_string()
        ? message->get<std::string>() : "JavaScript evaluation failed");
  }
  if (kind == "json") {
    if (!envelope.contains("value")) return Failure("CDP_MALFORMED_RESULT", "JSON evaluation result is missing value");
    return {true, {}, {}, envelope["value"], false};
  }
  if (kind == "undefined" || kind == "nonfinite" || kind == "bigint" || kind == "cyclic" ||
      kind == "node" || kind == "non_json") {
    Json descriptor = envelope;
    descriptor.erase("__kelpieRuntimeEnvelope");
    descriptor["type"] = kind;
    descriptor.erase("kind");
    return {true, {}, {}, std::move(descriptor), false};
  }
  return Failure("CDP_MALFORMED_RESULT", "Runtime.evaluate returned an unknown result descriptor");
}

DesktopDevToolsSession::Json DesktopDevToolsSession::TrustedKeyParams(const Json& input, bool key_up) {
  const std::string key = input.value("key", "");
  Json params = {{"type", key_up ? "keyUp" : "keyDown"}, {"key", key},
                 {"code", input.value("code", "")}, {"modifiers", ModifierMask(input)}};
  if (input.contains("windowsVirtualKeyCode")) params["windowsVirtualKeyCode"] = input["windowsVirtualKeyCode"];
  return params;
}

void DesktopDevToolsSession::OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int message_id, bool success,
                                                    const void* result, size_t result_size) {
  std::shared_ptr<Operation> operation;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = pending_.find(message_id);
    if (it == pending_.end()) return;
    operation = it->second;
    pending_.erase(it);
  }
  Complete(operation, ParseProtocolResult(success, result, result_size));
}

void DesktopDevToolsSession::OnDevToolsEvent(CefRefPtr<CefBrowser> browser, const CefString& method,
                                             const void* params, size_t params_size) {
  const std::string raw = params == nullptr ? std::string()
                                            : std::string(static_cast<const char*>(params), params_size);
  const Json parsed = Json::parse(raw, nullptr, false);
  if (parsed.is_discarded() || !parsed.is_object()) return;
  NetworkEventSink sink;
  std::optional<Json> event;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!browser_ || !browser_->IsSame(browser) || !network_sink_) return;
    event = network_events_.Observe(method.ToString(), parsed);
    sink = network_sink_;
  }
  if (event) sink(*event);
}

void DesktopDevToolsSession::OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) { CancelAll(); }

CefRefPtr<CefDictionaryValue> DesktopDevToolsSession::ToCefDictionary(const Json& object) {
  if (!object.is_object()) return nullptr;
  auto dictionary = CefDictionaryValue::Create();
  for (auto it = object.begin(); it != object.end(); ++it) dictionary->SetValue(it.key(), ToCefValue(it.value()));
  return dictionary;
}

CefRefPtr<CefValue> DesktopDevToolsSession::ToCefValue(const Json& value) {
  auto output = CefValue::Create();
  if (value.is_null()) output->SetNull();
  else if (value.is_boolean()) output->SetBool(value.get<bool>());
  else if (value.is_number_integer()) {
    const auto number = value.get<std::int64_t>();
    if (number >= std::numeric_limits<int>::min() && number <= std::numeric_limits<int>::max()) output->SetInt(static_cast<int>(number));
    else output->SetDouble(static_cast<double>(number));
  }
  else if (value.is_number_unsigned()) output->SetDouble(value.get<double>());
  else if (value.is_number_float()) output->SetDouble(value.get<double>());
  else if (value.is_string()) output->SetString(value.get<std::string>());
  else if (value.is_array()) {
    auto list = CefListValue::Create();
    for (const auto& item : value) list->SetValue(list->GetSize(), ToCefValue(item));
    output->SetList(list);
  } else if (value.is_object()) output->SetDictionary(ToCefDictionary(value));
  else output->SetNull();
  return output;
}

DesktopDevToolsSession::Result DesktopDevToolsSession::ParseProtocolResult(bool success, const void* result, size_t result_size) {
  const std::string raw = result == nullptr ? std::string() : std::string(static_cast<const char*>(result), result_size);
  const Json parsed = Json::parse(raw, nullptr, false);
  if (parsed.is_discarded() || !parsed.is_object()) return Failure("CDP_MALFORMED_RESULT", "CEF returned malformed DevTools JSON");
  if (!success) {
    const auto message = parsed.find("message");
    return Failure("DEVTOOLS_ERROR", message != parsed.end() && message->is_string()
        ? message->get<std::string>() : "DevTools method failed");
  }
  return {true, {}, {}, parsed, false};
}

void DesktopDevToolsSession::Complete(const std::shared_ptr<Operation>& operation, Result result) {
  std::lock_guard<std::mutex> lock(operation->mutex_);
  if (operation->done_ || operation->abandoned_) return;
  operation->result_ = std::move(result);
  operation->done_ = true;
  operation->completed_.notify_all();
}

bool DesktopDialogAdapter::Observe(CefRefPtr<CefBrowser> browser, cef_jsdialog_type_t type, const CefString& origin,
                                   const CefString& message, const CefString& default_prompt,
                                   CefRefPtr<CefJSDialogCallback> callback) {
  if (dialog_) {
    if (callback) callback->Continue(false, "");
    return true;
  }
  dialog_ = Dialog{browser, callback, {{"showing", true}, {"type", static_cast<int>(type)}, {"origin", origin.ToString()},
                                      {"message", message.ToString()}, {"defaultPrompt", default_prompt.ToString()}}};
  return true;
}

DesktopDialogAdapter::Json DesktopDialogAdapter::Current(CefRefPtr<CefBrowser> browser) const {
  if (!dialog_ || !dialog_->browser || !dialog_->browser->IsSame(browser)) return {{"showing", false}};
  return dialog_->value;
}

bool DesktopDialogAdapter::Handle(CefRefPtr<CefBrowser> browser, const Json& action, Json* result) {
  if (!dialog_ || !dialog_->browser || !dialog_->browser->IsSame(browser) || !dialog_->callback) return false;
  const bool accept = action.value("action", "dismiss") == "accept";
  dialog_->callback->Continue(accept, action.value("promptText", ""));
  dialog_.reset();
  if (result) *result = {{"handled", true}};
  return true;
}

void DesktopDialogAdapter::Reset(CefRefPtr<CefBrowser> browser) {
  if (dialog_ && dialog_->browser && dialog_->browser->IsSame(browser)) dialog_.reset();
}

}  // namespace kelpie
