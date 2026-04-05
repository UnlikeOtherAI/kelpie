#include "headless_shell.h"

#include <csignal>
#include <iostream>
#include <thread>

#include "linux_app.h"

namespace kelpie::linuxapp {
namespace {

LinuxApp* g_signal_app = nullptr;

void HandleSignal(int) {
  if (g_signal_app != nullptr) {
    g_signal_app->RequestShutdown();
  }
}

}  // namespace

HeadlessShell::HeadlessShell(LinuxApp& app) : app_(app) {}

int HeadlessShell::Run() {
  g_signal_app = &app_;
  std::signal(SIGINT, HandleSignal);
  std::signal(SIGTERM, HandleSignal);

  std::cout << "Kelpie headless browser running on port " << app_.port() << '\n';
  while (app_.IsRunning()) {
    app_.PumpBrowser();
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  g_signal_app = nullptr;
  return 0;
}

}  // namespace kelpie::linuxapp
