#include "kelpie/download_history.h"

#include <cassert>
#include <chrono>
#include <fstream>

int main() {
  namespace fs = std::filesystem;
  using State = kelpie::DownloadHistory::State;
  auto dir = fs::temp_directory_path() / ("kelpie-downloads-" + std::to_string(
      std::chrono::steady_clock::now().time_since_epoch().count()));
  assert(fs::create_directory(dir));
  kelpie::DownloadHistory history;
  std::vector<bool> visible;
  history.visibility_changed = [&](bool value) { visible.push_back(value); };
  auto first = history.Begin(1, "../../file.txt", dir);
  auto duplicate = history.Begin(2, "file.txt", dir);
  assert(first == dir / "file.txt");
  assert(duplicate == dir / "file (1).txt");
  std::ofstream(first) << "downloaded";
  history.Finish(1, true);
  assert(history.items().back().state == State::complete);
  history.ClearFinished();
  assert(history.items().size() == 1 && history.items()[0].id == 2);
  assert(fs::file_size(first) == 10);
  history.Finish(2, false);
  assert(history.items()[0].state == State::failed);
  assert(history.Begin(3, "dir\\CON.txt", dir) == dir / "_CON.txt");
  assert(history.Begin(4, "other", {}).empty());
  assert(history.items()[0].state == State::failed);
  history.Finish(3, false);
  history.ClearFinished();
  assert((visible == std::vector<bool>{true, false}));
  fs::remove(first);
  fs::remove(dir);
}
