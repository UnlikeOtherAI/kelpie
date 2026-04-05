#include "device_handler.h"

namespace kelpie {

DeviceHandler::DeviceHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void DeviceHandler::Register(DesktopRouter& router) const {
  router.Register("get-device-info", [this](const nlohmann::json&) { return GetDeviceInfo(); });
  router.Register("get-capabilities", [this](const nlohmann::json&) { return GetCapabilities(); });
}

nlohmann::json DeviceHandler::GetDeviceInfo() const {
  if (runtime_.device_info_provider == nullptr) {
    return Unsupported("get-device-info");
  }
  return runtime_.device_info_provider->GetDeviceInfo();
}

nlohmann::json DeviceHandler::GetCapabilities() const {
  if (!runtime_.capabilities_supplier) {
    return SuccessResponse({{"supported", nlohmann::json::array()},
                            {"partial", nlohmann::json::array()},
                            {"unsupported", nlohmann::json::array()}});
  }
  return runtime_.capabilities_supplier();
}

}  // namespace kelpie
