#include "sync_client.h"

#include <httplib.h>

#include <atomic>
#include <thread>

namespace kelpie::desktop_sync {

class SyncClient::Impl {
 public:
  Impl(const IpAddress& target, int port) : client(FormatIp(target), port) {
    client.set_connection_timeout(3, 0);
    client.set_write_timeout(10, 0);
    client.set_keep_alive(false);
    client.set_follow_location(false);
  }
  httplib::Client client;
  std::atomic<bool> stopped{false};
  std::atomic<bool> busy{false};
};

SyncClient::SyncClient(const IpAddress& target, int port) : impl_(std::make_unique<Impl>(target, port)) {}
SyncClient::~SyncClient() = default;

ClientReply SyncClient::Post(const std::string& path, const nlohmann::json& body, std::chrono::seconds read_timeout,
                             const std::map<std::string, std::string>& headers, std::size_t max_response) {
  ClientReply reply;
  impl_->busy = true;
  struct Idle {
    std::atomic<bool>& busy;
    ~Idle() { busy = false; }
  } idle{impl_->busy};
  if (impl_->stopped) return reply;
  impl_->client.set_read_timeout(static_cast<time_t>(read_timeout.count()), 0);
  httplib::Request request;
  request.method = "POST";
  request.path = path;
  request.body = body.dump();
  request.set_header("Content-Type", "application/json");
  for (const auto& [name, value] : headers) request.set_header(name, value);
  std::string received;
  bool oversized = false;
  request.content_receiver = [&](const char* data, std::size_t size, std::uint64_t, std::uint64_t) {
    if (received.size() + size > max_response) {
      oversized = true;
      return false;
    }
    received.append(data, size);
    return true;
  };
  httplib::Response response;
  httplib::Error error = httplib::Error::Success;
  if (!impl_->client.send(request, response, error) || oversized || impl_->stopped) return reply;
  reply.delivered = true;
  reply.status = response.status;
  auto parsed = nlohmann::json::parse(received, nullptr, false);
  if (!parsed.is_discarded()) reply.body = std::move(parsed);
  return reply;
}

void SyncClient::Stop() {
  impl_->stopped = true;
  // httplib's stop() only aborts a socket that is already in flight, so keep
  // stopping until a request that was just starting has observed it.
  const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  do {
    impl_->client.stop();
    if (!impl_->busy) return;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  } while (std::chrono::steady_clock::now() < until);
}

}  // namespace kelpie::desktop_sync
