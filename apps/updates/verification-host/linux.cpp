// Non-shipping host: shared GTK dialogs; Update is always simulated.
#include "../../linux/src/update_dialogs.h"
#include "../release_monitor.h"
#include <thread>
#include <iostream>

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  const auto state = std::filesystem::path(argc > 1 ? argv[1] : ".cache/update-verification-linux");
  std::filesystem::create_directories(state);
  kelpie::updates::ReleaseMonitor monitor("linux-x64-tar", "0.2.2", state / "skipped.json", [] {
    return R"([{"draft":false,"prerelease":false,"body":"<!-- kelpie-update: {\"target\":\"linux-x64-tar\",\"version\":\"0.2.3\",\"url\":\"https://github.com/UnlikeOtherAI/kelpie/releases/download/verification/kelpie.tar.gz\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"} -->"}])";
  });
  for (int attempt = 0; attempt < 100; ++attempt) {
    if (auto release = monitor.Tick()) {
      auto* dialog = kelpie::linuxapp::updates_ui::Prompt(nullptr, release->version.c_str());
      gtk_window_set_title(GTK_WINDOW(dialog), "Kelpie Update Verification");
      const int choice = gtk_dialog_run(GTK_DIALOG(dialog));
      gtk_widget_destroy(dialog);
      if (choice == 101 && !monitor.Skip(*release)) return 2;
      std::ofstream(state / "choice") << choice;
      if (choice == 100) {
        auto* progress = kelpie::linuxapp::updates_ui::Progress(nullptr);
        gtk_window_set_title(GTK_WINDOW(progress), "Kelpie Update Verification");
        gtk_dialog_add_button(GTK_DIALOG(progress), "Finish simulated update", GTK_RESPONSE_OK);
        gtk_dialog_run(GTK_DIALOG(progress));
        gtk_widget_destroy(progress);
      }
      std::cout << "choice=" << choice << ", isolated state=" << state << std::endl;
      return 0;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  std::cout << "No prompt: version is skipped." << std::endl;
  return 0;
}
