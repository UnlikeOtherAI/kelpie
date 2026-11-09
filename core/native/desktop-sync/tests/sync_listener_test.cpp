// Listener admission over real loopback sockets: refusals happen on the
// headers, before any body byte is read, and nothing but the three sync
// endpoints is ever routed.
#include <httplib.h>

#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdio>
#include <string>
#include <thread>

#include "sync_listener.h"

using namespace kelpie::desktop_sync;

namespace {

#ifdef _WIN32
using Socket = SOCKET;
void CloseSocket(Socket s) { closesocket(s); }
#else
using Socket = int;
void CloseSocket(Socket s) { close(s); }
#endif

struct FakeResponder : SyncResponder {
  std::atomic<int> hellos{0}, auths{0}, exchanges{0}, checks{0};
  SyncReply Hello(const std::string& body, const std::string&) override {
    ++hellos;
    return {200, {{"echo", body.size()}}};
  }
  SyncReply Auth(const std::string&) override {
    ++auths;
    return {200, nlohmann::json::object()};
  }
  bool SessionLive(const std::string& id) override {
    ++checks;
    return id == "live-session";
  }
  SyncReply Exchange(const std::string&, const std::string& body) override {
    ++exchanges;
    return {200, {{"echo", body.size()}}};
  }
};

Socket Connect(int port) {
  Socket s = socket(AF_INET, SOCK_STREAM, 0);
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_port = htons(static_cast<unsigned short>(port));
  inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
  const int connected = connect(s, reinterpret_cast<sockaddr*>(&address), sizeof(address));
  assert(connected == 0);
  return s;
}

void SendAll(Socket s, const std::string& data) {
  std::size_t sent = 0;
  while (sent < data.size()) {
    const auto n = send(s, data.data() + sent, static_cast<int>(data.size() - sent), 0);
    assert(n > 0);
    sent += static_cast<std::size_t>(n);
  }
}

// Reads until the server closes, at most `limit`. A refusal must arrive well
// before the listener's 5 s read timeout, proving it never waited for a body.
std::string ReadResponse(Socket s, std::chrono::milliseconds limit = std::chrono::milliseconds(3000)) {
  std::string out;
  const auto until = std::chrono::steady_clock::now() + limit;
  char buffer[4096];
  while (std::chrono::steady_clock::now() < until) {
    fd_set read_set;
    FD_ZERO(&read_set);
    FD_SET(s, &read_set);
    timeval timeout{0, 100000};
    const int ready = select(static_cast<int>(s + 1), &read_set, nullptr, nullptr, &timeout);
    if (ready <= 0) continue;
    const auto n = recv(s, buffer, sizeof(buffer), 0);
    if (n <= 0) break;
    out.append(buffer, static_cast<std::size_t>(n));
  }
  return out;
}

std::string Raw(int port, const std::string& request) {
  Socket s = Connect(port);
  SendAll(s, request);
  std::string response = ReadResponse(s);
  CloseSocket(s);
  return response;
}

int Status(const std::string& response) {
  if (response.size() < 12 || response.rfind("HTTP/1.1 ", 0) != 0) return 0;
  return std::stoi(response.substr(9, 3));
}

std::string Post(const std::string& path, const std::string& headers, const std::string& body = "") {
  return "POST " + path + " HTTP/1.1\r\nHost: peer\r\n" + headers + "\r\n" + body;
}

std::string Json(std::size_t length) { return "Content-Type: application/json\r\nContent-Length: " + std::to_string(length) + "\r\n"; }

void Admission() {
  FakeResponder responder;
  SyncListener::Limits limits;
  limits.handshake_read = std::chrono::seconds(1);
  SyncListener listener(&responder, limits);
  assert(listener.Start("127.0.0.1"));
  const int port = listener.port();
  assert(port > 0);

  // A valid hello is answered with no-store.
  const std::string ok = Raw(port, Post("/v1/sync/hello", Json(2), "{}"));
  assert(Status(ok) == 200 && ok.find("Cache-Control: no-store") != std::string::npos);
  assert(responder.hellos == 1);

  // Oversized bodies are refused on Content-Length alone, with no body sent.
  assert(Status(Raw(port, Post("/v1/sync/hello", Json(16 * 1024 + 1)))) == 413);
  assert(Status(Raw(port, Post("/v1/sync/auth", Json(64 * 1024)))) == 413);
  assert(Status(Raw(port, Post("/v1/sync/exchange", Json(4 * 1024 * 1024 + 1) +
                                                        "X-Kelpie-Sync-Session: live-session\r\n"))) == 413);
  // Exchange needs a live session before its body is read.
  assert(Status(Raw(port, Post("/v1/sync/exchange", Json(100)))) == 401);
  assert(Status(Raw(port, Post("/v1/sync/exchange", Json(100) + "X-Kelpie-Sync-Session: stale\r\n"))) == 401);
  assert(Status(Raw(port, Post("/v1/sync/exchange", Json(100) + "X-Kelpie-Sync-Session: live-session\r\n" +
                                                        "X-Kelpie-Sync-Session: live-session\r\n"))) == 401);
  assert(Status(Raw(port, Post("/v1/sync/exchange", Json(2) + "X-Kelpie-Sync-Session: live-session\r\n", "{}"))) == 200);
  assert(responder.exchanges == 1);

  // Browser-originated, chunked, ambiguous and mistyped requests are refused.
  assert(Status(Raw(port, Post("/v1/sync/hello", Json(2) + "Origin: https://evil.example\r\n", "{}"))) == 400);
  assert(Status(Raw(port, Post("/v1/sync/hello", "Content-Type: application/json\r\nTransfer-Encoding: chunked\r\n",
                               "2\r\n{}\r\n0\r\n\r\n"))) == 400);
  assert(Status(Raw(port, Post("/v1/sync/hello", Json(2) + "Content-Length: 2\r\n", "{}"))) == 400);
  assert(Status(Raw(port, Post("/v1/sync/hello", "Content-Type: application/json\r\n", ""))) == 400);
  assert(Status(Raw(port, Post("/v1/sync/hello", "Content-Type: text/plain\r\nContent-Length: 2\r\n", "{}"))) == 415);
  assert(Status(Raw(port, Post("/v1/sync/hello", Json(2) + "Expect: 100-continue\r\n"))) == 417);

  // Nothing else is routed: not the automation API, not GET, not MCP.
  assert(Status(Raw(port, Post("/v1/get-cookies", Json(2), "{}"))) == 404);
  assert(Status(Raw(port, Post("/mcp", Json(2), "{}"))) == 404);
  assert(Status(Raw(port, "GET /v1/sync/hello HTTP/1.1\r\nHost: peer\r\n\r\n")) == 405);
  assert(Status(Raw(port, "GET /health HTTP/1.1\r\nHost: peer\r\n\r\n")) == 404);

  // A body that arrives after the read deadline is refused.
  Socket slow = Connect(port);
  SendAll(slow, Post("/v1/sync/hello", Json(10), "{\"a\":"));
  std::this_thread::sleep_for(std::chrono::milliseconds(1300));
  SendAll(slow, "1}   ");
  assert(Status(ReadResponse(slow)) == 408);
  CloseSocket(slow);
  assert(responder.hellos == 1);  // no refused request ever reached the responder
  assert(responder.auths == 0);

  // Ten hellos a minute per source address.
  int accepted = 0;
  for (int i = 0; i < 12; ++i) {
    if (Status(Raw(port, Post("/v1/sync/hello", Json(2), "{}"))) == 200) ++accepted;
  }
  assert(accepted == 8);  // 2 already counted: the first hello and the late one
  assert(Status(Raw(port, Post("/v1/sync/hello", Json(2), "{}"))) == 429);
  listener.Stop();
  assert(listener.port() == 0);
}

}  // namespace

int main() {
  Admission();
  std::puts("sync_listener_test passed");
  return 0;
}
