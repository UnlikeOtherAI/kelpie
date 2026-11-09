#pragma once
#include <string>
#include <vector>

namespace kelpie::linuxapp {
// Chromium changes argv storage and /proc/self/cmdline. Keep owned launch tokens
// before entering Chromium so an update can restart the same profile and port.
inline std::vector<std::string> CaptureLaunchArguments(int argc, char* const argv[]) {
  std::vector<std::string> arguments;
  for (int index = 1; index < argc; ++index) arguments.emplace_back(argv[index]);
  return arguments;
}
}
