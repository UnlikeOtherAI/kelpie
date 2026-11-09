#pragma once

#include <chrono>
#include <thread>
#include <httplib.h>

namespace kelpie {

// Bound the whole request read, including a peer that keeps sending individual
// bytes just before a socket timeout. Browser work and response writes retain
// their own deadlines after the complete request has been read.
class ControlRequestStream final : public httplib::Stream {
 public:
  ControlRequestStream(socket_t socket, std::chrono::seconds budget, time_t write_seconds, time_t write_microseconds)
      : stream_(socket, 0, 10000, write_seconds, write_microseconds), deadline_(std::chrono::steady_clock::now() + budget) {}
  bool is_readable() const override { return std::chrono::steady_clock::now() < deadline_ && stream_.is_readable(); }
  bool is_writable() const override { return stream_.is_writable(); }
  ssize_t read(char* data, std::size_t size) override {
    while (std::chrono::steady_clock::now() < deadline_) {
      const auto count = stream_.read(data, size);
      if (count >= 0) return count;
      if (!httplib::detail::is_socket_alive(stream_.socket())) return -1;
      // Errors as well as timeouts must not turn a broken socket into a busy loop.
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return -1;
  }
  ssize_t write(const char* data, std::size_t size) override { return stream_.write(data, size); }
  void get_remote_ip_and_port(std::string& ip, int& port) const override { stream_.get_remote_ip_and_port(ip, port); }
  void get_local_ip_and_port(std::string& ip, int& port) const override { stream_.get_local_ip_and_port(ip, port); }
  socket_t socket() const override { return stream_.socket(); }
 private:
  httplib::detail::SocketStream stream_;
  std::chrono::steady_clock::time_point deadline_;
};

class ControlHttpServer final : public httplib::Server {
 public:
  std::chrono::seconds request_read_budget{5};
  void CloseUnstartedListener() {
    const auto socket = svr_sock_.exchange(INVALID_SOCKET);
    if (socket != INVALID_SOCKET) { httplib::detail::shutdown_socket(socket); httplib::detail::close_socket(socket); }
  }
 private:
  bool process_and_close_socket(socket_t socket) override {
    struct SocketOwner {
      socket_t socket;
      ~SocketOwner() { httplib::detail::shutdown_socket(socket); httplib::detail::close_socket(socket); }
    } owner{socket};
    ControlRequestStream stream(socket, request_read_budget, write_timeout_sec_, write_timeout_usec_);
    std::string remote, local;
    int remote_port = 0, local_port = 0;
    stream.get_remote_ip_and_port(remote, remote_port);
    stream.get_local_ip_and_port(local, local_port);
    bool closed = true;
    // Stateless HTTP/MCP uses one complete request per connection. This keeps
    // each connection's total read budget independent of later requests.
    return process_request(stream, remote, remote_port, local, local_port, true, closed, nullptr);
  }
};
}  // namespace kelpie
