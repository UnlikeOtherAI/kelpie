#pragma once

// Outgoing sync requests. The caller has already applied the address rule
// (OrderTargets); the client adds bounded timeouts and response sizes, no
// redirects and no keep-alive, and can be aborted from another thread.

#include <chrono>
#include <cstddef>
#include <map>
#include <memory>
#include <mutex>
#include <string>

#include <nlohmann/json.hpp>

#include "sync_net.h"

namespace kelpie::desktop_sync {

struct ClientReply {
  bool delivered = false;  // a complete HTTP response arrived
  int status = 0;
  nlohmann::json body;     // discarded (null) unless it is valid JSON
};

class SyncClient {
 public:
  SyncClient(const IpAddress& target, int port);
  ~SyncClient();
  SyncClient(const SyncClient&) = delete;
  SyncClient& operator=(const SyncClient&) = delete;

  ClientReply Post(const std::string& path, const nlohmann::json& body, std::chrono::seconds read_timeout,
                   const std::map<std::string, std::string>& headers = {},
                   std::size_t max_response = 4 * 1024 * 1024);
  // Aborts the request in flight, if any, and refuses later ones.
  void Stop();

  class Impl;

 private:
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie::desktop_sync
