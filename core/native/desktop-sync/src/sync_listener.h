#pragma once

// The sync-only LAN listener. A separate httplib::Server on an ephemeral port
// that serves exactly POST /v1/sync/hello, /v1/sync/auth and
// /v1/sync/exchange. It never routes to DesktopRouter or the automation API.
//
// Admission runs on the request headers, before any body byte is read: the
// address rule, Origin/Transfer-Encoding/duplicate Content-Length refusal,
// per-endpoint body limits, the hello rate limit and, for exchange, a live
// X-Kelpie-Sync-Session. Every connection carries one request.

#include <chrono>
#include <cstddef>
#include <memory>
#include <string>

#include <nlohmann/json.hpp>

namespace kelpie::desktop_sync {

struct SyncReply {
  int status = 200;
  nlohmann::json body = nlohmann::json::object();
};

inline SyncReply ErrorReply(int status, const char* code) { return {status, {{"error", code}}}; }

class SyncResponder {
 public:
  virtual ~SyncResponder() = default;
  virtual SyncReply Hello(const std::string& body, const std::string& source) = 0;
  virtual SyncReply Auth(const std::string& body) = 0;
  // Checked before an exchange body is read.
  virtual bool SessionLive(const std::string& session_id) = 0;
  virtual SyncReply Exchange(const std::string& session_id, const std::string& body) = 0;
};

struct SyncListenerLimits {
  std::size_t handshake_body = 16 * 1024;
  std::size_t exchange_body = 4 * 1024 * 1024;
  std::chrono::seconds handshake_read{5};
  std::chrono::seconds exchange_read{15};
  int hello_per_source_per_minute = 10;
  int hello_per_minute = 60;
  std::size_t workers = 32;
};

class SyncListener {
 public:
  using Limits = SyncListenerLimits;

  explicit SyncListener(SyncResponder* responder, Limits limits = Limits());
  ~SyncListener();
  SyncListener(const SyncListener&) = delete;
  SyncListener& operator=(const SyncListener&) = delete;

  // Binds an ephemeral port. An empty address binds every interface,
  // dual-stack when IPv6 is available. False when nothing could be bound.
  bool Start(const std::string& bind_address);
  // Stops accepting and joins the workers. Callers wake long-polls first.
  void Stop();
  int port() const;

  class Impl;

 private:
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie::desktop_sync
