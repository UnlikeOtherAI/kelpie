#include "desktop_devtools.h"

#include <algorithm>
#include <ctime>
#include <iomanip>
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

cef_cookie_same_site_t ParseSameSite(const std::string& value) {
  if (value == "Lax") return CEF_COOKIE_SAME_SITE_LAX_MODE;
  if (value == "Strict") return CEF_COOKIE_SAME_SITE_STRICT_MODE;
  if (value == "None") return CEF_COOKIE_SAME_SITE_NO_RESTRICTION;
  return CEF_COOKIE_SAME_SITE_UNSPECIFIED;
}

std::optional<time_t> ParseIsoUtc(const std::string& value) {
  if (value.size() < 20 || value.back() != 'Z') return std::nullopt;
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
  return {{"expression", expression}, {"awaitPromise", true}, {"returnByValue", true}, {"userGesture", true}};
}

DesktopDevToolsSession::Result DesktopDevToolsSession::ParseEvaluateResult(const Result& protocol_result) {
  if (!protocol_result.ok) return protocol_result;
  if (protocol_result.value.contains("exceptionDetails")) {
    const auto& details = protocol_result.value["exceptionDetails"];
    return Failure("JAVASCRIPT_ERROR", details.value("text", "JavaScript evaluation failed"));
  }
  const auto& remote = protocol_result.value.value("result", Json::object());
  if (!remote.is_object()) return Failure("CDP_MALFORMED_RESULT", "Runtime.evaluate did not return a remote object");
  if (remote.value("type", "") == "undefined") return {true, {}, {}, {{"type", "undefined"}}, false};
  if (remote.contains("value")) return {true, {}, {}, remote["value"], false};
  return {true, {}, {}, {{"type", remote.value("type", "unknown")},
                           {"description", remote.value("description", "")},
                           {"unserializableValue", remote.value("unserializableValue", "")}}, false};
}

DesktopDevToolsSession::Json DesktopDevToolsSession::ScreenshotParams(const Json& options) {
  Json params = {{"format", options.value("format", "png")}, {"captureBeyondViewport", false}};
  if (options.contains("quality")) params["quality"] = options["quality"];
  return params;
}

DesktopDevToolsSession::Result DesktopDevToolsSession::ParseScreenshotResult(const Result& protocol_result) {
  if (!protocol_result.ok) return protocol_result;
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
  else if (value.is_number_integer()) output->SetInt(value.get<int>());
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
  if (!success) return Failure("DEVTOOLS_ERROR", parsed.value("message", "DevTools method failed"));
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
  CefCookie cookie{};
  cookie.name = input.value("name", "");
  cookie.value = input.value("value", "");
  cookie.domain = input.value("domain", "");
  cookie.path = input.value("path", "/");
  cookie.httponly = input.value("httpOnly", false) ? 1 : 0;
  cookie.secure = input.value("secure", false) ? 1 : 0;
  cookie.same_site = ParseSameSite(input.value("sameSite", ""));
  if (input.contains("expires") && input["expires"].is_string()) {
    const auto expires = ParseIsoUtc(input["expires"].get<std::string>());
    if (!expires || !cef_time_from_timet(*expires, &cookie.expires)) return std::nullopt;
    cookie.has_expires = 1;
  }
  return cookie;
}

DesktopCookieAdapter::Json DesktopCookieAdapter::FromCefCookie(const CefCookie& cookie) {
  Json output = {{"name", cookie.name.ToString()}, {"value", cookie.value.ToString()}, {"domain", cookie.domain.ToString()},
                 {"path", cookie.path.ToString()}, {"httpOnly", cookie.httponly != 0}, {"secure", cookie.secure != 0},
                 {"sameSite", SameSiteName(cookie.same_site)}};
  if (cookie.has_expires) {
    double expires = 0;
    if (cef_time_to_doublet(&cookie.expires, &expires)) output["expiresUnixSeconds"] = expires;
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
