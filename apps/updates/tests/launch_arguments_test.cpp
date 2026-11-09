#include "../../linux/src/launch_arguments.h"
#include <cstring>
#include <iostream>

int main(int argc, char* argv[]) {
  const std::vector<std::string> expected{
      "--profile-dir", "/tmp/Kelpie profile", "--port", "18537",
      "--readiness-file", "/tmp/Kelpie profile/readiness.json", "--url", "https://example.com"};
  const auto captured = kelpie::linuxapp::CaptureLaunchArguments(argc, argv);
  if (captured != expected) return 1;
  // Reproduce Chromium replacing process argument storage after startup.
  for (int index = 0; index < argc; ++index) std::memset(argv[index], ' ', std::strlen(argv[index]));
  if (captured != expected) {
    std::cerr << "An update lost launch options when process arguments changed\n";
    return 1;
  }
  std::cout << "Original profile, port, readiness path and URL survived argv mutation\n";
}
