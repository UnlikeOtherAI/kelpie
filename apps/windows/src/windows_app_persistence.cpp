// Profile persistence for WindowsApp: settings, the tab session and the
// bookmark/history stores. Every write is an atomic replacement made by the
// owner of the exclusive ProfileSession lock.
#include "windows_app.h"

#include <fstream>
#include <limits>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <shlobj.h>

namespace kelpie::windows {
namespace {

std::filesystem::path RoamingAppDataPath() {
  wchar_t buffer[MAX_PATH]{};
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, buffer))) {
    return std::filesystem::path(buffer) / "Kelpie";
  }
  return std::filesystem::temp_directory_path() / "Kelpie";
}

bool LoadJsonFile(const std::filesystem::path& path, nlohmann::json& output) {
  std::ifstream input(path);
  if (!input.good()) {
    return false;
  }
  try {
    input >> output;
    return true;
  } catch (...) {
    output = nlohmann::json::object();
    return false;
  }
}

bool SaveJsonFileAtomically(const std::filesystem::path& path, const nlohmann::json& value,
                          std::uint64_t epoch) {
  std::error_code error;
  std::filesystem::create_directories(path.parent_path(), error);
  if (error) return false;
  const std::filesystem::path temporary = path.wstring() + L".tmp." + std::to_wstring(epoch);
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    if (!output.good()) return false;
    output << value.dump(2);
    output.flush();
    if (!output.good()) return false;
  }
  HANDLE handle = CreateFileW(temporary.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return false;
  const bool flushed = FlushFileBuffers(handle) != FALSE;
  CloseHandle(handle);
  if (!flushed) return false;
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temporary.c_str());
    return false;
  }
  return true;
}

bool SameSession(const SessionSnapshot& left, const SessionSnapshot& right) {
  if (left.next_tab_id != right.next_tab_id || left.tabs.size() != right.tabs.size()) return false;
  for (std::size_t index = 0; index < left.tabs.size(); ++index) {
    const SessionTab& a = left.tabs[index];
    const SessionTab& b = right.tabs[index];
    if (a.id != b.id || a.url != b.url || a.active != b.active || a.name != b.name ||
        a.partition != b.partition || a.persistent != b.persistent) {
      return false;
    }
  }
  return true;
}
}  // namespace

void WindowsApp::ResolveProfileDirectory() {
  if (config_.profile_dir.empty()) {
    config_.profile_dir = RoamingAppDataPath();
  }
  std::filesystem::create_directories(config_.profile_dir);
  device_info_provider_.SetProfileDir(config_.profile_dir);
}

void WindowsApp::LoadSettings() {
  nlohmann::json settings;
  if (!LoadJsonFile(config_.profile_dir / "settings.json", settings)) {
    return;
  }
  if (!config_.port_overridden) {
    config_.port = settings.value("port", config_.port);
  }
  if (!config_.url_overridden) {
    config_.initial_url = settings.value("startup_url", config_.initial_url);
  }
  config_.isolate_new_tabs = settings.value("isolate_new_tabs", config_.isolate_new_tabs);
  if (const auto placement = ParseWindowPlacement(settings.value("window", nlohmann::json()))) {
    window_placement_ = placement;
    // An explicit --width/--height wins over the remembered size.
    if (!config_.width_overridden) config_.width = placement->frame.right - placement->frame.left;
    if (!config_.height_overridden) config_.height = placement->frame.bottom - placement->frame.top;
  }
}

void WindowsApp::SaveSettings() const {
  nlohmann::json settings = {{"port", config_.port}, {"profile_dir", config_.profile_dir.u8string()},
                             {"startup_url", config_.initial_url},
                             {"isolate_new_tabs", config_.isolate_new_tabs}};
  if (window_placement_) settings["window"] = SerializeWindowPlacement(*window_placement_);
  SaveJsonFileAtomically(config_.profile_dir / "settings.json", settings, persistence_epoch_ + 1);
}


void WindowsApp::LoadSession() {
  nlohmann::json value;
  if (!LoadJsonFile(config_.profile_dir / "session.json", value)) return;
  SessionSnapshot parsed;
  if (ParseSessionSnapshot(value, &parsed)) session_snapshot_ = std::move(parsed);
}

void WindowsApp::SaveSession() {
  if (!desktop_app_) return;
  DesktopEngine::SessionState state;
  if (!desktop_app_->engine().GetSessionState(&state, std::chrono::seconds(2)).ok || state.tabs.empty()) return;
  if (session_snapshot_.epoch == std::numeric_limits<std::uint64_t>::max()) return;
  SessionSnapshot next;
  next.epoch = session_snapshot_.epoch + 1;
  next.next_tab_id = state.next_tab_id;
  for (const auto& tab : state.tabs) {
    SessionTab entry{tab.id, tab.url, tab.active};
    entry.name = tab.name;
    entry.partition = tab.partition;
    entry.persistent = tab.persistent;
    next.tabs.push_back(std::move(entry));
  }
  if (SameSession(session_snapshot_, next)) return;
  if (SaveJsonFileAtomically(config_.profile_dir / "session.json", SerializeSessionSnapshot(next), next.epoch)) session_snapshot_ = std::move(next);
}

void WindowsApp::LoadStores() {
  nlohmann::json epoch;
  if (LoadJsonFile(config_.profile_dir / "stores-epoch.json", epoch)) {
    persistence_epoch_ = epoch.value("epoch", std::uint64_t{0});
  }
  // The exclusive ProfileSession lock is held before this method runs. Legacy
  // files remain readable; all later writes are atomic replacements by this owner.
  if (!desktop_app_) return;
  nlohmann::json bookmarks;
  if (LoadJsonFile(config_.profile_dir / "bookmarks.json", bookmarks)) {
    desktop_app_->bookmark_store().LoadJson(bookmarks.dump());
  }
  nlohmann::json history;
  if (LoadJsonFile(config_.profile_dir / "history.json", history)) {
    desktop_app_->history_store().LoadJson(history.dump());
  }
}

void WindowsApp::SaveStores() {
  if (!desktop_app_) return;
  const std::uint64_t next_epoch = persistence_epoch_ + 1;
  const auto bookmarks = nlohmann::json::parse(desktop_app_->bookmark_store().ToJson(), nullptr, false);
  const auto history = nlohmann::json::parse(desktop_app_->history_store().ToJson(), nullptr, false);
  if (bookmarks.is_discarded() || history.is_discarded()) return;
  if (!SaveJsonFileAtomically(config_.profile_dir / "bookmarks.json", bookmarks, next_epoch) ||
      !SaveJsonFileAtomically(config_.profile_dir / "history.json", history, next_epoch)) return;
  if (SaveJsonFileAtomically(config_.profile_dir / "stores-epoch.json", {{"epoch", next_epoch}}, next_epoch)) {
    persistence_epoch_ = next_epoch;
  }
}

}  // namespace kelpie::windows
