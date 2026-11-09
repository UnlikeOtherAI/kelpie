#pragma once

#include <cerrno>
#include <cstddef>
#include <cstring>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace kelpie::linuxapp {

// An abstract socket is machine-wide, independent of profile, user and port.
// The kernel releases it on exit, including SIGKILL, without stale-file cleanup.
class StandaloneInstance {
 public:
  explicit StandaloneInstance(const std::string& name = "UnlikeOtherAI.Kelpie.Standalone") {
    socket_ = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (socket_ < 0) { error_ = errno; return; }
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    if (name.size() >= sizeof(address.sun_path) - 1) { error_ = ENAMETOOLONG; return; }
    std::memcpy(address.sun_path + 1, name.data(), name.size());
    const auto size = static_cast<socklen_t>(offsetof(sockaddr_un, sun_path) + 1 + name.size());
    if (bind(socket_, reinterpret_cast<const sockaddr*>(&address), size) != 0) error_ = errno;
  }
  ~StandaloneInstance() { if (socket_ >= 0) close(socket_); }
  StandaloneInstance(const StandaloneInstance&) = delete;
  StandaloneInstance& operator=(const StandaloneInstance&) = delete;
  int error() const { return error_; }

 private:
  int socket_ = -1;
  int error_ = 0;
};

}  // namespace kelpie::linuxapp
