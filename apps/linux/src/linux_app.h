#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {

struct AppConfig {
  bool headless = false;
  int port = 8420;
  std::string profile_dir;
  std::string url;
  int width = 1920;
  int height = 1080;
};

class LinuxApp {
 public:
  using json = nlohmann::json;

  LinuxApp(AppConfig config, int argc, char* argv[]);
  ~LinuxApp();

  int Run();
  void RequestShutdown();
  bool IsRunning() const;
  void PumpBrowser();
  bool AttachBrowserHost(std::uintptr_t parent_window, int width, int height);
  void ResizeBrowserHost(int width, int height);
  bool HasNativeBrowser() const;
  bool FocusBrowser(bool focused);
  bool SendBrowserMouseMove(int x, int y, bool mouse_leave);
  bool SendBrowserMouseClick(int x, int y, int button, bool mouse_up, int click_count);
  bool SendBrowserMouseWheel(int x, int y, int delta_x, int delta_y);
  void SetFullscreen(bool fullscreen);
  bool IsFullscreen() const;
  bool WantsFullscreen() const;
  void ReportFullscreenState(bool fullscreen);

  const AppConfig& config() const;
  int port() const;
  bool GuiAvailable() const;
  bool MdnsActive() const;
  bool ScreenshotSupported() const;
  std::string MdnsStatusText() const;
  std::string RuntimeMode() const;

  bool Navigate(const std::string& url);
  bool GoBack();
  bool GoForward();
  bool Reload();
  bool CanGoBack() const;
  bool CanGoForward() const;
  bool IsLoading() const;
  std::string CurrentUrl() const;
  std::string CurrentTitle() const;
  std::vector<std::uint8_t> SnapshotBytes() const;
  std::string HomeUrl() const;
  void SetHomeUrl(const std::string& url);

  void AddBookmark(const std::string& title, const std::string& url);
  void RemoveBookmark(const std::string& id);
  void ClearBookmarks();
  void ClearHistory();

  std::string BookmarksJson() const;
  std::string HistoryJson() const;
  json ConsoleMessages(const std::optional<std::string>& level = std::nullopt) const;
  json NetworkEntries(const std::optional<std::string>& method = std::nullopt,
                      const std::optional<std::string>& type = std::nullopt,
                      const std::optional<std::string>& source = std::nullopt) const;
  json DeviceInfo() const;
  json Capabilities() const;
  json HandleApiRequest(std::string_view endpoint, const json& params, int* status_code);

  void ShowToast(const std::string& message);
  std::string ConsumeToast();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie::linuxapp
