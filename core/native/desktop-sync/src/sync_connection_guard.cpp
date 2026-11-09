#include "sync_connection_guard.h"

#include <algorithm>

#include "sync_net.h"

namespace kelpie::desktop_sync {
namespace {

constexpr auto kWatchInterval = std::chrono::milliseconds(50);

// The connection a guarded worker thread is serving.
struct CurrentConnection {
  ConnectionWatchdog* watchdog = nullptr;
  ConnectionWatchdog::Connection* connection = nullptr;
};
thread_local CurrentConnection current;

// One key per address, so ports and IPv4-mapped spellings cannot split a source.
std::string SourceKey(const std::string& address) {
  auto parsed = ParseIp(address);
  if (!parsed) return address;
  parsed->scope = 0;
  return FormatIp(*parsed);
}

}  // namespace

ConnectionWatchdog::ConnectionWatchdog() : thread_([this] { Run(); }) {}

ConnectionWatchdog::~ConnectionWatchdog() {
  {
    std::lock_guard lock(mutex_);
    stopping_ = true;
  }
  wake_.notify_all();
  if (thread_.joinable()) thread_.join();
}

std::shared_ptr<ConnectionWatchdog::Connection> ConnectionWatchdog::Watch(socket_t socket,
                                                                           Clock::time_point deadline) {
  auto connection = std::make_shared<Connection>();
  connection->socket = socket;
  connection->deadline = deadline;
  std::lock_guard lock(mutex_);
  connections_.push_back(connection);
  return connection;
}

void ConnectionWatchdog::Rearm(Connection* connection, std::optional<Clock::time_point> deadline) {
  std::lock_guard lock(mutex_);
  if (!connection->fired) connection->deadline = deadline;
}

void ConnectionWatchdog::Forget(const std::shared_ptr<Connection>& connection) {
  std::lock_guard lock(mutex_);
  connections_.erase(std::remove(connections_.begin(), connections_.end(), connection), connections_.end());
}

void ConnectionWatchdog::ShutdownAll() {
  std::lock_guard lock(mutex_);
  for (auto& connection : connections_) {
    if (connection->fired) continue;
    connection->fired = true;
    httplib::detail::shutdown_socket(connection->socket);
  }
}

void ConnectionWatchdog::Run() {
  std::unique_lock lock(mutex_);
  while (!stopping_) {
    wake_.wait_for(lock, kWatchInterval);
    const auto now = Clock::now();
    for (auto& connection : connections_) {
      if (connection->fired || !connection->deadline || now < *connection->deadline) continue;
      // Progress does not matter: the phase is over. The worker's blocked
      // read fails and it closes the socket after Forget().
      connection->fired = true;
      httplib::detail::shutdown_socket(connection->socket);
    }
  }
}

void GuardedServer::SetDeadline(std::optional<Clock::time_point> deadline) {
  if (current.watchdog && current.connection) current.watchdog->Rearm(current.connection, deadline);
}

bool GuardedServer::Enter(const std::string& source) {
  std::lock_guard lock(sources_mutex_);
  auto& active = active_by_source_[source];
  if (active >= policy_.connections_per_source) {
    if (active == 0) active_by_source_.erase(source);
    return false;
  }
  ++active;
  return true;
}

void GuardedServer::Leave(const std::string& source) {
  std::lock_guard lock(sources_mutex_);
  const auto it = active_by_source_.find(source);
  if (it == active_by_source_.end()) return;
  if (--it->second == 0) active_by_source_.erase(it);
}

bool GuardedServer::process_and_close_socket(socket_t sock) {
  std::string remote_addr, local_addr;
  int remote_port = 0, local_port = 0;
  httplib::detail::get_remote_ip_and_port(sock, remote_addr, remote_port);
  httplib::detail::get_local_ip_and_port(sock, local_addr, local_port);
  const std::string source = SourceKey(remote_addr);
  bool served = false;
  // Both checks run before any byte is read; a refusal just closes the socket.
  if (Enter(source)) {
    if (!policy_.admit || policy_.admit(remote_addr, local_addr)) {
      const auto watched = watchdog_.Watch(sock, Clock::now() + policy_.header_deadline);
      current = {&watchdog_, watched.get()};
      served = httplib::detail::process_server_socket(
          svr_sock_, sock, keep_alive_max_count_, keep_alive_timeout_sec_, read_timeout_sec_, read_timeout_usec_,
          write_timeout_sec_, write_timeout_usec_,
          [&](httplib::Stream& stream, bool close_connection, bool& connection_closed) {
            return process_request(stream, remote_addr, remote_port, local_addr, local_port, close_connection,
                                   connection_closed, nullptr);
          });
      current = {};
      watchdog_.Forget(watched);
    }
    Leave(source);
  }
  httplib::detail::shutdown_socket(sock);
  httplib::detail::close_socket(sock);
  return served;
}

}  // namespace kelpie::desktop_sync
