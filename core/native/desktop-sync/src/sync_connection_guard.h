#pragma once

// Connection-level guards for the sync listener, applied before cpp-httplib
// reads a single byte.
//
// cpp-httplib v0.18.5 bounds each socket read (read timeout) but not a whole
// request, so a peer that trickles one header byte per read can hold a worker
// indefinitely, and enough of them hold every worker. GuardedServer overrides
// httplib::Server's per-connection entry point (process_and_close_socket, a
// private virtual) to:
//   1. cap concurrent connections per source address;
//   2. apply the address rule to the accepted socket;
//   3. serve the request under an absolute deadline per phase, which a
//      watchdog thread enforces by shutting the socket down, however steadily
//      the peer is still sending. The blocked read then fails and the worker
//      closes the connection.
// Phases: headers (from accept), body (set once headers are parsed), the
// handler (unwatched; the service bounds it), and the response write.

#include <httplib.h>

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace kelpie::desktop_sync {

class ConnectionWatchdog {
 public:
  using Clock = std::chrono::steady_clock;
  struct Connection {
    socket_t socket = INVALID_SOCKET;
    std::optional<Clock::time_point> deadline;  // nullopt: not watched right now
    bool fired = false;
  };

  ConnectionWatchdog();
  ~ConnectionWatchdog();
  ConnectionWatchdog(const ConnectionWatchdog&) = delete;
  ConnectionWatchdog& operator=(const ConnectionWatchdog&) = delete;

  std::shared_ptr<Connection> Watch(socket_t socket, Clock::time_point deadline);
  void Rearm(Connection* connection, std::optional<Clock::time_point> deadline);
  // Must run before the socket is closed, so a late shutdown cannot hit a reused handle.
  void Forget(const std::shared_ptr<Connection>& connection);
  void ShutdownAll();

 private:
  void Run();

  std::mutex mutex_;
  std::condition_variable wake_;
  std::vector<std::shared_ptr<Connection>> connections_;
  bool stopping_ = false;
  std::thread thread_;
};

class GuardedServer final : public httplib::Server {
 public:
  using Clock = ConnectionWatchdog::Clock;
  struct Policy {
    std::size_t connections_per_source = 8;
    std::chrono::milliseconds header_deadline{5000};
    // Address rule on (peer address, local address) text, as cpp-httplib reports them.
    std::function<bool(const std::string& peer, const std::string& local)> admit;
  };

  explicit GuardedServer(Policy policy) : policy_(std::move(policy)) {}

  // Moves the deadline of the connection the calling worker serves; nullopt
  // stops watching it. A no-op outside a guarded worker.
  static void SetDeadline(std::optional<Clock::time_point> deadline);
  // Shuts down every watched connection, so Stop() never waits on a slow peer.
  void ShutdownConnections() { watchdog_.ShutdownAll(); }

 private:
  bool process_and_close_socket(socket_t sock) override;
  bool Enter(const std::string& source);
  void Leave(const std::string& source);

  Policy policy_;
  ConnectionWatchdog watchdog_;
  std::mutex sources_mutex_;
  std::map<std::string, std::size_t> active_by_source_;
};

}  // namespace kelpie::desktop_sync
