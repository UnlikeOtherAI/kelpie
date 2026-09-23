#pragma once

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>

#include <nlohmann/json.hpp>

#include "include/cef_browser.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_registration.h"

namespace kelpie {

class DesktopNetworkEventAdapter {
 public:
  using Json = nlohmann::json;

  std::optional<Json> Observe(const std::string& method, const Json& params);
  void Clear();
  std::size_t pending_count() const { return requests_.size(); }

 private:
  struct Request {
    std::string url;
    std::string method = "GET";
    std::string type = "Other";
    std::string content_type;
    std::string initiator = "browser";
    std::string timestamp;
    double started_at = 0;
    int status = 0;
  };

  static constexpr std::size_t kMaxPendingRequests = 512;
  std::unordered_map<std::string, Request> requests_;
};

class DesktopDevToolsSession final : public CefDevToolsMessageObserver {
 public:
  using Json = nlohmann::json;
  using NetworkEventSink = std::function<void(const Json&)>;

  struct Result {
    bool ok = false;
    std::string error_code;
    std::string message;
    Json value = Json::object();
    bool operation_may_have_completed = false;
  };

  class Operation {
   public:
    Operation(const Operation&) = delete;
    Operation& operator=(const Operation&) = delete;

   private:
    friend class DesktopDevToolsSession;
    explicit Operation(int message_id) : message_id_(message_id) {}

    int message_id_;
    std::mutex mutex_;
    std::condition_variable completed_;
    bool done_ = false;
    bool abandoned_ = false;
    Result result_;
  };

  DesktopDevToolsSession();
  void Attach(CefRefPtr<CefBrowser> browser, NetworkEventSink network_sink);
  std::shared_ptr<Operation> Begin(CefRefPtr<CefBrowser> browser,
                                   const std::string& method,
                                   const Json& params);
  Result Wait(const std::shared_ptr<Operation>& operation, std::chrono::milliseconds timeout);
  void CancelAll();

  static Json EvaluateParams(const std::string& expression);
  static Result ParseEvaluateResult(const Result& protocol_result);
  static Json TrustedKeyParams(const Json& input, bool key_up);

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                              int message_id,
                              bool success,
                              const void* result,
                              size_t result_size) override;
  void OnDevToolsEvent(CefRefPtr<CefBrowser> browser,
                       const CefString& method,
                       const void* params,
                       size_t params_size) override;
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser> browser) override;

 private:
  ~DesktopDevToolsSession() override;

  static CefRefPtr<CefDictionaryValue> ToCefDictionary(const Json& object);
  static CefRefPtr<CefValue> ToCefValue(const Json& value);
  static Result ParseProtocolResult(bool success, const void* result, size_t result_size);
  void Complete(const std::shared_ptr<Operation>& operation, Result result);

  std::mutex mutex_;
  int next_message_id_ = 1;
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> registration_;
  std::unordered_map<int, std::shared_ptr<Operation>> pending_;
  DesktopNetworkEventAdapter network_events_;
  NetworkEventSink network_sink_;

  IMPLEMENT_REFCOUNTING(DesktopDevToolsSession);
};

class DesktopDialogAdapter {
 public:
  using Json = nlohmann::json;

  bool Observe(CefRefPtr<CefBrowser> browser,
               cef_jsdialog_type_t type,
               const CefString& origin,
               const CefString& message,
               const CefString& default_prompt,
               CefRefPtr<CefJSDialogCallback> callback);
  Json Current(CefRefPtr<CefBrowser> browser) const;
  bool Handle(CefRefPtr<CefBrowser> browser, const Json& action, Json* result);
  void Reset(CefRefPtr<CefBrowser> browser);

 private:
  struct Dialog {
    CefRefPtr<CefBrowser> browser;
    CefRefPtr<CefJSDialogCallback> callback;
    Json value;
  };
  std::optional<Dialog> dialog_;
};

}  // namespace kelpie
