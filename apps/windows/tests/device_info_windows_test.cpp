#include "device_info_windows.h"

#include <windows.h>

#include <filesystem>

int main() {
  const std::filesystem::path profile = std::filesystem::current_path() /
      ("device-info-test-" + std::to_string(GetCurrentProcessId()));
  std::error_code error;
  std::filesystem::create_directories(profile, error);
  if (error) return 1;

  kelpie::windows::DeviceInfoWindows provider(profile);
  provider.Configure(8421, 1440, 900, "0.1.1-test");
  const nlohmann::json device = provider.GetDeviceInfo();
  const kelpie::StringMap metadata = provider.GetMdnsMetadata();
  std::filesystem::remove_all(profile, error);
  if (!device.is_object() || device.value("platform", "") != "windows" ||
      device.value("engine", "") != "chromium" || device.value("port", 0) != 8421 ||
      device.value("width", 0) != 1440 || device.value("height", 0) != 900 ||
      device.value("version", "") != "0.1.1-test" || device.value("ip", "") != "127.0.0.1" ||
      device.value("controlMode", "") != "loopback" || !device.contains("mcp") ||
      !device["mcp"].is_object() || device["mcp"].value("endpoint", "") != "/mcp" ||
      device["mcp"].value("stdio", true)) {
    return 2;
  }
  return metadata.at("platform") == "windows" && metadata.at("engine") == "chromium" &&
      metadata.at("port") == "8421" && metadata.at("version") == "0.1.1-test" ? 0 : 3;
}
