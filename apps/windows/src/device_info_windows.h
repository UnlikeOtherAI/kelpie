#pragma once

#include <filesystem>
#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/types.h"

namespace kelpie::windows {

struct DeviceInfo {
  std::string id;
  std::string name;
  std::string model;
  std::string platform = "windows";
  std::string engine = "chromium";
  std::string ip_address;
  std::string os_version;
  std::string app_version;
  std::uint64_t total_memory_bytes = 0;
  std::uint64_t available_memory_bytes = 0;
  int width = 0;
  int height = 0;
  int port = 0;
};

nlohmann::json ToJson(const DeviceInfo& device_info);
StringMap ToTxtRecord(const DeviceInfo& device_info);

class DeviceInfoWindows {
 public:
  explicit DeviceInfoWindows(std::filesystem::path profile_dir);

  void SetProfileDir(std::filesystem::path profile_dir);
  DeviceInfo Collect(int port, int width, int height, const std::string& app_version) const;

 private:
  std::filesystem::path profile_dir_;
};

}  // namespace kelpie::windows
