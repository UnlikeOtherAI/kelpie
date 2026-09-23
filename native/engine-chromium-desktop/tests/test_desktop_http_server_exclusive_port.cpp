// Windows only: the control listener must own its loopback port outright.
// cpp-httplib's default options leave the socket shareable there, so a second
// Kelpie bound the same address and connections split between two processes.
#include "kelpie/desktop_http_server.h"

#include <cassert>
#include <chrono>
#include <thread>

#include <httplib.h>

#include "kelpie/desktop_mcp_server.h"
#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"

namespace {

// What an unfixed Kelpie, or any cpp-httplib default server, holds: a
// listener with SO_REUSEADDR set.
class ReusableListener {
 public:
  explicit ReusableListener(int port) {
    socket_ = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    assert(socket_ != INVALID_SOCKET);
    const int reuse = 1;
    const int reuse_result = setsockopt(socket_, SOL_SOCKET, SO_REUSEADDR,
                                        reinterpret_cast<const char*>(&reuse), sizeof(reuse));
    assert(reuse_result == 0);
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<u_short>(port));
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(socket_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
        ::listen(socket_, SOMAXCONN) != 0) {
      bind_error_ = WSAGetLastError();
      return;
    }
    int length = sizeof(address);
    const int name_result = getsockname(socket_, reinterpret_cast<sockaddr*>(&address), &length);
    assert(name_result == 0);
    port_ = ntohs(address.sin_port);
  }
  ReusableListener(const ReusableListener&) = delete;
  ReusableListener& operator=(const ReusableListener&) = delete;
  ~ReusableListener() { closesocket(socket_); }

  bool listening() const { return port_ != 0; }
  int port() const { return port_; }
  int bind_error() const { return bind_error_; }

 private:
  SOCKET socket_ = INVALID_SOCKET;
  int port_ = 0;
  int bind_error_ = 0;
};

struct Harness {
  Harness() {
    mcp.SetRouter(&router);
    mcp.SetRegistry(&registry);
  }
  kelpie::DesktopRouter router;
  kelpie::McpRegistry registry;
  kelpie::DesktopMcpServer mcp;
};

kelpie::DesktopHttpServer::Config ConfigFor(int port) {
  kelpie::DesktopHttpServer::Config config;
  config.port = port;
  config.control_token = "test-capability";
  return config;
}

bool Start(kelpie::DesktopHttpServer& server, Harness& harness, int port) {
  server.SetRouter(&harness.router);
  server.SetMcpServer(&harness.mcp);
  return server.Start(ConfigFor(port));
}

bool Healthy(int port) {
  httplib::Client client("127.0.0.1", port);
  for (int attempt = 0; attempt < 50; ++attempt) {
    const auto health = client.Get("/health");
    if (health && health->status == 200) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return false;
}

}  // namespace

int main() {
  WSADATA wsa{};
  const int startup_result = WSAStartup(MAKEWORD(2, 2), &wsa);
  assert(startup_result == 0);
  Harness harness;

  // A shareable holder, as an unfixed Kelpie leaves it, must refuse the bind.
  {
    ReusableListener holder(0);
    assert(holder.listening());
    kelpie::DesktopHttpServer contender;
    assert(!Start(contender, harness, holder.port()));
    assert(!contender.IsRunning());
    assert(contender.bound_port() == 0);
  }

  kelpie::DesktopHttpServer owner;
  assert(Start(owner, harness, 0));
  const int port = owner.bound_port();
  assert(port > 0);
  assert(Healthy(port));

  // A second Kelpie on the same port fails instead of sharing it.
  {
    kelpie::DesktopHttpServer second;
    assert(!Start(second, harness, port));
    assert(!second.IsRunning());
  }
  // So does an unfixed Kelpie arriving second: Windows answers WSAEACCES.
  {
    ReusableListener late(port);
    assert(!late.listening());
    assert(late.bind_error() == WSAEACCES);
  }
  assert(Healthy(port));

  // Exclusive use must not keep the port once an orderly stop has closed a
  // listener that served requests; restarting on the same port still works.
  owner.Stop();
  kelpie::DesktopHttpServer restarted;
  assert(Start(restarted, harness, port));
  assert(Healthy(port));
  restarted.Stop();

  WSACleanup();
  return 0;
}
