#include "headless_shell.h"

#include <csignal>
#include <iostream>
#include <thread>

#include "linux_app.h"

namespace kelpie::linuxapp {
namespace {

volatile std::sig_atomic_t g_stop = 0;

void HandleSignal(int) {
  g_stop = 1;
}

}  // namespace

HeadlessShell::HeadlessShell(LinuxApp& app) : app_(app) {}

int HeadlessShell::Run() {
  g_stop = 0;
  std::signal(SIGINT, HandleSignal);
  std::signal(SIGTERM, HandleSignal);

  std::cout << "Kelpie headless browser running on port " << app_.port() << '\n';
  while (app_.IsRunning()) {
    if (g_stop) app_.RequestShutdown();
    app_.PumpBrowser();
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return 0;
}

}  // namespace kelpie::linuxapp
