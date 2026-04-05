#pragma once

#include <atomic>
#include <string>
#include <thread>

#include "device_info_linux.h"

namespace kelpie::linuxapp {

struct MdnsServiceConfig {
  DeviceInfoSnapshot device;
  int port = 0;
  int width = 0;
  int height = 0;
  std::string version;
  std::string runtime_mode;
};

class MdnsAvahi {
 public:
  MdnsAvahi();
  ~MdnsAvahi();

  bool Start(const MdnsServiceConfig& config);
  void Stop();

  bool IsRunning() const;
  std::string ServiceName() const;
  std::string LastError() const;

 private:
  std::string service_name_;
  std::string last_error_;
  std::atomic<bool> running_{false};

#if KELPIE_LINUX_HAS_AVAHI
  void Run(const MdnsServiceConfig& config);
  std::thread thread_;
  void* simple_poll_ = nullptr;
  void* client_ = nullptr;
  void* group_ = nullptr;
#endif
};

}  // namespace kelpie::linuxapp
