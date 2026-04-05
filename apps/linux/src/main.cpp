#include <cstdlib>
#include <iostream>
#include <string>

#include "linux_app.h"
#include "kelpie/cef_app_factory.h"

#if KELPIE_LINUX_HAS_CEF
#include "include/cef_app.h"
#endif

namespace {

std::string DefaultProfileDir() {
  const char* home = std::getenv("HOME");
  return std::string(home == nullptr ? "" : home) + "/.config/kelpie";
}

bool ParseInt(const char* value, int* output) {
  if (value == nullptr || output == nullptr) {
    return false;
  }
  char* end = nullptr;
  const long parsed = std::strtol(value, &end, 10);
  if (end == value || *end != '\0') {
    return false;
  }
  *output = static_cast<int>(parsed);
  return true;
}

void PrintHelp() {
  std::cout
      << "kelpie-linux [options]\n"
      << "  --headless\n"
      << "  --port PORT\n"
      << "  --profile-dir DIR\n"
      << "  --url URL\n"
      << "  --width WIDTH\n"
      << "  --height HEIGHT\n";
}

}  // namespace

int main(int argc, char* argv[]) {
#if KELPIE_LINUX_HAS_CEF
  CefMainArgs main_args(argc, argv);
  CefRefPtr<CefApp> cef_app = kelpie::CreateDesktopCefApp();
  const int subprocess_code = CefExecuteProcess(main_args, cef_app, nullptr);
  if (subprocess_code >= 0) {
    return subprocess_code;
  }
#endif

  kelpie::linuxapp::AppConfig config;
  config.port = 8420;
  config.profile_dir = DefaultProfileDir();
  config.width = 1920;
  config.height = 1080;

  for (int index = 1; index < argc; ++index) {
    const std::string arg = argv[index];
    if (arg == "--headless") {
      config.headless = true;
    } else if (arg == "--port" && index + 1 < argc) {
      if (!ParseInt(argv[++index], &config.port)) {
        std::cerr << "Invalid --port value\n";
        return 1;
      }
    } else if (arg == "--profile-dir" && index + 1 < argc) {
      config.profile_dir = argv[++index];
    } else if (arg == "--url" && index + 1 < argc) {
      config.url = argv[++index];
    } else if (arg == "--width" && index + 1 < argc) {
      if (!ParseInt(argv[++index], &config.width)) {
        std::cerr << "Invalid --width value\n";
        return 1;
      }
    } else if (arg == "--height" && index + 1 < argc) {
      if (!ParseInt(argv[++index], &config.height)) {
        std::cerr << "Invalid --height value\n";
        return 1;
      }
    } else if (arg == "--help") {
      PrintHelp();
      return 0;
    } else {
      std::cerr << "Unknown argument: " << arg << '\n';
      PrintHelp();
      return 1;
    }
  }

  kelpie::linuxapp::LinuxApp app(config, argc, argv);
  return app.Run();
}
