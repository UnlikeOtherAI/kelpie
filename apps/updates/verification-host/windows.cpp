// Non-shipping host: the real native dialogs, isolated preferences, no installer.
#include <windows.h>
#include "../../windows/src/update_dialogs.h"
#include "../release_monitor.h"
#include <iostream>
#include <thread>

#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

int main(int argc, char** argv) {
  wchar_t executable[32768]{};
  if (!GetModuleFileNameW(nullptr, executable, 32768)) return 4;
  const auto state = argc > 1 ? std::filesystem::path(argv[1]) :
      std::filesystem::path(executable).parent_path() / "verification-state";
  std::filesystem::create_directories(state);
  kelpie::updates::ReleaseMonitor monitor("windows-x64", "0.2.2", state / "skipped.json", [] {
    return R"([{"draft":false,"prerelease":false,"body":"<!-- kelpie-update: {\"target\":\"windows-x64\",\"version\":\"0.2.3\",\"url\":\"https://github.com/UnlikeOtherAI/kelpie/releases/download/verification/kelpie.zip\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"} -->"}])";
  });
  // A second check in the same process must remain suppressed after any choice.
  for (int attempt = 0; attempt < 100; ++attempt) {
    if (auto release = monitor.Tick()) {
      int choice = 102;
      if (FAILED(kelpie::windows::updates_ui::Prompt(nullptr, L"0.2.3", choice, L"Kelpie Update Verification"))) return 1;
      if (choice == 101 && !monitor.Skip(*release)) return 2;
      if (monitor.Tick(kelpie::updates::ReleaseMonitor::Clock::now() + std::chrono::hours(7))) return 3;
      std::ofstream(state / "choice") << choice;
      if (choice == 100) {
        const auto progress = kelpie::windows::updates_ui::Progress(nullptr);
        MessageBoxW(progress, L"Simulated update completed. No installer ran and no Kelpie installation changed.",
            L"Kelpie Update Verification", MB_OK);
        DestroyWindow(progress);
      }
      std::cout << "choice=" << choice << ", isolated state=" << state << std::endl;
      return 0;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  std::cout << "No prompt: version is skipped." << std::endl;
  return 0;
}
