#pragma once

#include <cstdint>
#include <string>

#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {

struct DeviceInfoSnapshot {
  std::string id;
  std::string name;
  std::string model;
  std::string manufacturer = "Generic";
  std::string platform = "linux";
  std::string engine = "chromium";
  std::string os_name;
  std::string os_version;
  std::string architecture;
  std::string ip;
  std::int64_t total_memory = 0;
  std::int64_t available_memory = 0;
};

class DeviceInfoLinux {
 public:
  explicit DeviceInfoLinux(std::string profile_dir);

  DeviceInfoSnapshot Collect() const;
  nlohmann::json ToJson(const DeviceInfoSnapshot& snapshot,
                        int port,
                        int width,
                        int height,
                        bool mdns_active,
                        bool http_active,
                        const std::string& mdns_name,
                        const std::string& version,
                        std::int64_t uptime_seconds) const;

 private:
  std::string profile_dir_;
};

}  // namespace kelpie::linuxapp
