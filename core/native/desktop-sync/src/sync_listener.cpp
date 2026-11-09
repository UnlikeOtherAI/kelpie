#include "sync_listener.h"

#include <httplib.h>

#include <deque>
#include <map>
#include <mutex>
#include <thread>
#include <vector>

#include "sync_net.h"

namespace kelpie::desktop_sync {
namespace {

using Clock = std::chrono::steady_clock;

constexpr const char* kHello = "/v1/sync/hello";
constexpr const char* kAuth = "/v1/sync/auth";
constexpr const char* kExchange = "/v1/sync/exchange";
constexpr const char* kSessionHeader = "X-Kelpie-Sync-Session";
constexpr std::size_t kMaxSessionHeader = 64;

void Send(httplib::Response& response, const SyncReply& reply) {
  response.status = reply.status;
  response.set_header("Cache-Control", "no-store");
  response.set_content(reply.body.dump(), "application/json");
}

// Exactly one Content-Length of plain decimal digits.
std::optional<std::size_t> ContentLength(const httplib::Request& request) {
  if (request.get_header_value_count("Content-Length") != 1) return std::nullopt;
  const std::string text = request.get_header_value("Content-Length");
  if (text.empty() || text.size() > 12 || text.find_first_not_of("0123456789") != std::string::npos) {
    return std::nullopt;
  }
  return static_cast<std::size_t>(std::stoull(text));
}

bool JsonContentType(const httplib::Request& request) {
  if (request.get_header_value_count("Content-Type") != 1) return false;
  const std::string value = request.get_header_value("Content-Type");
  return value.substr(0, value.find(';')) == "application/json";
}

// 10 hellos a minute per source address and 60 in total.
class HelloRateLimit {
 public:
  HelloRateLimit(int per_source, int total) : per_source_(per_source), total_(total) {}
  bool Allow(const std::string& source) {
    std::lock_guard lock(mutex_);
    const auto now = Clock::now();
    while (!all_.empty() && now - all_.front() >= std::chrono::minutes(1)) all_.pop_front();
    for (auto it = by_source_.begin(); it != by_source_.end();) {
      auto& times = it->second;
      while (!times.empty() && now - times.front() >= std::chrono::minutes(1)) times.pop_front();
      it = times.empty() ? by_source_.erase(it) : std::next(it);
    }
    auto& times = by_source_[source];
    if (static_cast<int>(all_.size()) >= total_ || static_cast<int>(times.size()) >= per_source_) {
      if (times.empty()) by_source_.erase(source);
      return false;
    }
    all_.push_back(now);
    times.push_back(now);
    return true;
  }

 private:
  std::mutex mutex_;
  int per_source_, total_;
  std::deque<Clock::time_point> all_;
  std::map<std::string, std::deque<Clock::time_point>> by_source_;
};

}  // namespace

class SyncListener::Impl {
 public:
  Impl(SyncResponder* responder, Limits limits)
      : responder_(responder), limits_(limits),
        hello_limit_(limits.hello_per_source_per_minute, limits.hello_per_minute) {}

  bool Start(const std::string& bind_address);
  void Stop();
  int port = 0;

 private:
  // Header-only admission. Returns false after writing the refusal; the
  // unread body is discarded when the one-request connection closes.
  bool Admit(const httplib::Request& request, httplib::Response& response);
  bool AddressAllowed(const httplib::Request& request);
  std::optional<std::string> ReadBody(const httplib::ContentReader& reader, std::size_t limit,
                                      std::chrono::seconds deadline, SyncReply* refusal) const;
  void Route(const char* path, const httplib::Request& request, httplib::Response& response,
             const httplib::ContentReader& reader);

  SyncResponder* responder_;
  Limits limits_;
  HelloRateLimit hello_limit_;
  httplib::Server server_;
  std::thread thread_;
  bool running_ = false;
  std::mutex interfaces_mutex_;
  std::vector<InterfaceAddress> interfaces_;
  Clock::time_point interfaces_read_{};
};

bool SyncListener::Impl::AddressAllowed(const httplib::Request& request) {
  const auto peer = ParseIp(request.remote_addr);
  if (!peer) return false;
  if (IsLoopback(*peer)) return true;
  std::vector<InterfaceAddress> interfaces;
  {
    std::lock_guard lock(interfaces_mutex_);
    // Interfaces change with DHCP, Wi-Fi roaming and VPNs; re-read every few seconds.
    if (Clock::now() - interfaces_read_ > std::chrono::seconds(5) || interfaces_.empty()) {
      interfaces_ = EnumerateInterfaces();
      interfaces_read_ = Clock::now();
    }
    interfaces = interfaces_;
  }
  return PeerAllowed(*peer, ParseIp(request.local_addr), interfaces);
}

bool SyncListener::Impl::Admit(const httplib::Request& request, httplib::Response& response) {
  const std::string& path = request.path;
  const bool exchange = path == kExchange;
  if (path != kHello && path != kAuth && !exchange) {
    Send(response, ErrorReply(404, "NOT_FOUND"));
    return false;
  }
  if (request.method != "POST") {
    response.set_header("Allow", "POST");
    Send(response, ErrorReply(405, "METHOD_NOT_ALLOWED"));
    return false;
  }
  if (!AddressAllowed(request)) {
    Send(response, ErrorReply(403, "FORBIDDEN"));
    return false;
  }
  if (request.has_header("Origin") || request.has_header("Transfer-Encoding")) {
    Send(response, ErrorReply(400, "INVALID_REQUEST"));
    return false;
  }
  if (request.has_header("Expect")) {
    Send(response, ErrorReply(417, "INVALID_REQUEST"));
    return false;
  }
  const auto length = ContentLength(request);
  if (!length) {
    Send(response, ErrorReply(400, "INVALID_REQUEST"));
    return false;
  }
  if (*length > (exchange ? limits_.exchange_body : limits_.handshake_body)) {
    Send(response, ErrorReply(413, "TOO_LARGE"));
    return false;
  }
  if (!JsonContentType(request)) {
    Send(response, ErrorReply(415, "INVALID_CONTENT_TYPE"));
    return false;
  }
  if (path == kHello && !hello_limit_.Allow(request.remote_addr)) {
    Send(response, ErrorReply(429, "RATE_LIMITED"));
    return false;
  }
  if (exchange) {
    const std::string session = request.get_header_value(kSessionHeader);
    if (request.get_header_value_count(kSessionHeader) != 1 || session.empty() ||
        session.size() > kMaxSessionHeader || !responder_->SessionLive(session)) {
      Send(response, ErrorReply(401, "SYNC_SESSION"));
      return false;
    }
  }
  return true;
}

std::optional<std::string> SyncListener::Impl::ReadBody(const httplib::ContentReader& reader, std::size_t limit,
                                                        std::chrono::seconds deadline, SyncReply* refusal) const {
  std::string body;
  const auto until = Clock::now() + deadline;
  bool late = false, large = false;
  const bool read = reader([&](const char* data, std::size_t size) {
    if (Clock::now() > until) { late = true; return false; }
    if (body.size() + size > limit) { large = true; return false; }
    body.append(data, size);
    return true;
  });
  if (read && !late && !large) return body;
  *refusal = large ? ErrorReply(413, "TOO_LARGE") : late ? ErrorReply(408, "TIMEOUT") : ErrorReply(400, "INVALID_REQUEST");
  return std::nullopt;
}

void SyncListener::Impl::Route(const char* path, const httplib::Request& request, httplib::Response& response,
                               const httplib::ContentReader& reader) {
  const bool exchange = std::string(path) == kExchange;
  SyncReply refusal;
  const auto body = ReadBody(reader, exchange ? limits_.exchange_body : limits_.handshake_body,
                             exchange ? limits_.exchange_read : limits_.handshake_read, &refusal);
  if (!body) {
    Send(response, refusal);
    return;
  }
  if (std::string(path) == kHello) {
    Send(response, responder_->Hello(*body, request.remote_addr));
  } else if (std::string(path) == kAuth) {
    Send(response, responder_->Auth(*body));
  } else {
    Send(response, responder_->Exchange(request.get_header_value(kSessionHeader), *body));
  }
}

bool SyncListener::Impl::Start(const std::string& bind_address) {
  if (running_) return false;
  const std::size_t workers = limits_.workers;
  server_.new_task_queue = [workers]() -> httplib::TaskQueue* { return new httplib::ThreadPool(workers, workers * 4); };
  server_.set_keep_alive_max_count(1);
  server_.set_read_timeout(5, 0);
  server_.set_write_timeout(10, 0);
  server_.set_payload_max_length(limits_.exchange_body);
  // Never invite a body before admission has seen the headers.
  server_.set_expect_100_continue_handler([](const httplib::Request&, httplib::Response&) { return 417; });
  server_.set_pre_routing_handler([this](const httplib::Request& request, httplib::Response& response) {
    return Admit(request, response) ? httplib::Server::HandlerResponse::Unhandled
                                    : httplib::Server::HandlerResponse::Handled;
  });
  server_.set_exception_handler([](const httplib::Request&, httplib::Response& response, std::exception_ptr) {
    Send(response, ErrorReply(500, "INTERNAL"));
  });
  for (const char* path : {kHello, kAuth, kExchange}) {
    server_.Post(path, [this, path](const httplib::Request& request, httplib::Response& response,
                                    const httplib::ContentReader& reader) { Route(path, request, response, reader); });
  }
  if (bind_address.empty()) {
    server_.set_ipv6_v6only(false);
    port = server_.bind_to_any_port("::");
    if (port <= 0) port = server_.bind_to_any_port("0.0.0.0");
  } else {
    port = server_.bind_to_any_port(bind_address);
  }
  if (port <= 0) {
    port = 0;
    return false;
  }
  thread_ = std::thread([this] { server_.listen_after_bind(); });
  server_.wait_until_ready();
  if (!server_.is_running()) {
    if (thread_.joinable()) thread_.join();
    port = 0;
    return false;
  }
  running_ = true;
  return true;
}

void SyncListener::Impl::Stop() {
  if (!running_) return;
  server_.stop();
  if (thread_.joinable()) thread_.join();
  running_ = false;
  port = 0;
}

SyncListener::SyncListener(SyncResponder* responder, Limits limits)
    : impl_(std::make_unique<Impl>(responder, limits)) {}
SyncListener::~SyncListener() { Stop(); }
bool SyncListener::Start(const std::string& bind_address) { return impl_->Start(bind_address); }
void SyncListener::Stop() { impl_->Stop(); }
int SyncListener::port() const { return impl_->port; }

}  // namespace kelpie::desktop_sync
