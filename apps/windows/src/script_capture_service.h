#pragma once
#include <windows.h>
#include <filesystem>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include "kelpie/desktop_app.h"
namespace kelpie::windows {
class ScriptNativeOverlay;
class WindowsScriptService : public std::enable_shared_from_this<WindowsScriptService> {
 public:
  using Json = nlohmann::json;
  using Marshal = std::function<bool(std::function<bool()>)>;
  using DocumentGuard=std::function<bool(const Json&)>;
  WindowsScriptService(HWND viewport, HWND owner, Marshal marshal, DocumentGuard guard);
  ~WindowsScriptService();
  void Configure(DesktopApp::Config& config);
  Json Publish(const std::filesystem::path& path, const std::string& mime, Json metadata,
               const std::string& run, const std::string& owner);
  Json Read(const Json& body, const std::string& owner);
  void Discard(const std::string& run,const std::string& owner);
  void Show(const Json& presentation, std::function<void()> stop);
 private:
  struct Entry {
    std::filesystem::path path;
    std::string run, owner;
    Json manifest;
    BY_HANDLE_FILE_INFORMATION identity{};
    std::chrono::steady_clock::time_point created;
  };
  void Expire();
  std::mutex mutex_;
  std::map<std::string, Entry> entries_;
  HWND viewport_, owner_;
  Marshal marshal_;
  DocumentGuard guard_;
  std::unique_ptr<ScriptNativeOverlay> overlay_;
};
BY_HANDLE_FILE_INFORMATION CaptureFileIdentity(const std::filesystem::path& path);
bool RemoveCaptureFile(const std::filesystem::path& path,const BY_HANDLE_FILE_INFORMATION& expected);
std::filesystem::path CreatePrivateCaptureDirectory(const std::string& run);
}
