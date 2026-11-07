#pragma once

#include <string>

namespace kelpie {

inline constexpr const char* kBridgeConsoleMessageName = "kelpie.bridge.console";
inline constexpr const char* kBridgeNetworkMessageName = "kelpie.bridge.network";

std::string ConsoleBridgeScript();
std::string NetworkBridgeScript();
std::string CombinedBridgeScript();

}  // namespace kelpie
