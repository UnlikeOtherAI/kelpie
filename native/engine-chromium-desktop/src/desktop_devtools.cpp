#include "desktop_devtools.h"

#include <algorithm>
#include <cctype>
#include <ctime>
#include <iomanip>
#include <limits>
#include <sstream>
#include <utility>
#include <vector>

#include "include/cef_task.h"
#include "include/cef_values.h"
#include "include/internal/cef_time.h"

namespace kelpie {
namespace {

DesktopDevToolsSession::Result Failure(std::string code, std::string message, bool may_have_completed = false) {
  return {false, std::move(code), std::move(message), nlohmann::json::object(), may_have_completed};
}

std::string SameSiteName(cef_cookie_same_site_t value) {
  switch (value) {
    case CEF_COOKIE_SAME_SITE_LAX_MODE: return "Lax";
    case CEF_COOKIE_SAME_SITE_STRICT_MODE: return "Strict";
    case CEF_COOKIE_SAME_SITE_NO_RESTRICTION: return "None";
    default: return "Unspecified";
  }
}

std::optional<cef_cookie_same_site_t> ParseSameSite(const std::string& value) {
  if (value == "Lax") return CEF_COOKIE_SAME_SITE_LAX_MODE;
  if (value == "Strict") return CEF_COOKIE_SAME_SITE_STRICT_MODE;
  if (value == "None") return CEF_COOKIE_SAME_SITE_NO_RESTRICTION;
  return std::nullopt;
}

std::optional<time_t> ParseIsoUtc(const std::string& value) {
  if (value.size() < 20 || value.back() != 'Z') return std::nullopt;
  const std::string fraction = value.substr(19, value.size() - 20);
  if (!fraction.empty() && (fraction.front() != '.' || fraction.size() == 1 ||
      !std::all_of(fraction.begin() + 1, fraction.end(), [](unsigned char character) { return std::isdigit(character) != 0; }))) {
    return std::nullopt;
  }
  std::tm parsed{};
  std::istringstream stream(value.substr(0, 19));
  stream >> std::get_time(&parsed, "%Y-%m-%dT%H:%M:%S");
  if (stream.fail()) return std::nullopt;
#if defined(_WIN32)
  return _mkgmtime(&parsed);
#else
  return timegm(&parsed);
#endif
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

}  // namespace

DesktopDevToolsSession::DesktopDevToolsSession() = default;
DesktopDevToolsSession::~DesktopDevToolsSession() { CancelAll(); }

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

std::optional<DesktopDevToolsSession::Json> DesktopDevToolsSession::ScreenshotParams(const Json& options) {
  if (!options.is_object()) return std::nullopt;
  const auto format_value = options.find("format");
  if (format_value != options.end() && !format_value->is_string()) return std::nullopt;
  const std::string format = format_value == options.end() ? "png" : format_value->get<std::string>();
  if (format != "png") return std::nullopt;
  Json params = {{"format", "png"}, {"captureBeyondViewport", false}};
  if (options.contains("quality")) params["quality"] = options["quality"];
  return params;
}

DesktopDevToolsSession::Result DesktopDevToolsSession::ParseScreenshotResult(const Result& protocol_result) {
  if (!protocol_result.ok) return protocol_result;
  if (!protocol_result.value.is_object()) return Failure("CDP_MALFORMED_RESULT", "Page.captureScreenshot did not return an object");
  const auto data = protocol_result.value.find("data");
  if (data == protocol_result.value.end() || !data->is_string() || data->get<std::string>().empty()) {
    return Failure("CDP_MALFORMED_RESULT", "Page.captureScreenshot did not return encoded PNG data");
  }
  return {true, {}, {}, {{"mimeType", "image/png"}, {"data", *data}}, false};
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

std::optional<CefCookie> DesktopCookieAdapter::ToCefCookie(const Json& input) {
  if (!input.is_object() || !input.contains("name") || !input["name"].is_string() ||
      !input.contains("value") || !input["value"].is_string()) return std::nullopt;
  if (input["name"].get<std::string>().empty()) return std::nullopt;
  for (const char* name : {"domain", "path"}) {
    if (input.contains(name) && !input[name].is_string()) return std::nullopt;
  }
  for (const char* name : {"httpOnly", "secure"}) {
    if (input.contains(name) && !input[name].is_boolean()) return std::nullopt;
  }
  CefCookie cookie{};
  cookie.size = sizeof(cookie);
  CefString(&cookie.name) = input.value("name", "");
  CefString(&cookie.value) = input.value("value", "");
  CefString(&cookie.domain) = input.value("domain", "");
  CefString(&cookie.path) = input.value("path", "/");
  cookie.httponly = input.value("httpOnly", false) ? 1 : 0;
  cookie.secure = input.value("secure", false) ? 1 : 0;
  if (input.contains("sameSite")) {
    if (!input["sameSite"].is_string()) return std::nullopt;
    const auto same_site = ParseSameSite(input["sameSite"].get<std::string>());
    if (!same_site) return std::nullopt;
    cookie.same_site = *same_site;
  } else {
    cookie.same_site = CEF_COOKIE_SAME_SITE_UNSPECIFIED;
  }
  if (input.contains("expires")) {
    if (!input["expires"].is_string()) return std::nullopt;
    const auto expires = ParseIsoUtc(input["expires"].get<std::string>());
    cef_time_t expiration_time{};
    if (!expires || !cef_time_from_timet(*expires, &expiration_time) ||
        !cef_time_to_basetime(&expiration_time, &cookie.expires)) return std::nullopt;
    cookie.has_expires = 1;
  }
  return cookie;
}

DesktopCookieAdapter::Json DesktopCookieAdapter::FromCefCookie(const CefCookie& cookie) {
  Json output = {{"name", CefString(&cookie.name).ToString()}, {"value", CefString(&cookie.value).ToString()}, {"domain", CefString(&cookie.domain).ToString()},
                 {"path", CefString(&cookie.path).ToString()}, {"httpOnly", cookie.httponly != 0}, {"secure", cookie.secure != 0},
                 {"sameSite", SameSiteName(cookie.same_site)}};
  if (cookie.has_expires) {
    cef_time_t expiration_time{};
    double expires = 0;
    if (cef_time_from_basetime(cookie.expires, &expiration_time) && cef_time_to_doublet(&expiration_time, &expires)) {
      output["expiresUnixSeconds"] = expires;
    }
  }
  return output;
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
