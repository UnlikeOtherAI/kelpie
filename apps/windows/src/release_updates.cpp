#include <windows.h>
#include <winhttp.h>
#include <commctrl.h>
#include <shlobj.h>
#include "release_updates.h"
#include "update_dialogs.h"
#include "windows_utf.h"
#include "../../updates/release_monitor.h"
#include <fstream>
#include <memory>

namespace kelpie::windows {
namespace {
struct CloseInternet { void operator()(void* value) const { if (value) WinHttpCloseHandle(value); } };
using Internet = std::unique_ptr<void, CloseInternet>;
void Require(bool ok) { if (!ok) throw std::runtime_error("Update check failed"); }
std::string Fetch() {
  Internet session(WinHttpOpen(L"Kelpie update check", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
  Require(bool(session));
  Require(WinHttpSetTimeouts(session.get(), 2500, 2500, 2500, 2500));
  Internet connection(WinHttpConnect(session.get(), L"api.github.com", 443, 0));
  Require(bool(connection));
  Internet request(WinHttpOpenRequest(connection.get(), L"GET",
      L"/repos/UnlikeOtherAI/kelpie/releases?per_page=100", nullptr,
      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE));
  Require(bool(request));
  DWORD disabled = WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_REDIRECTS;
  Require(WinHttpSetOption(request.get(), WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled)));
  Require(WinHttpSendRequest(request.get(), L"Accept: application/vnd.github+json\r\n", -1,
      WINHTTP_NO_REQUEST_DATA, 0, 0, 0));
  Require(WinHttpReceiveResponse(request.get(), nullptr));
  DWORD status = 0, length = sizeof(status);
  Require(WinHttpQueryHeaders(request.get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status, &length, WINHTTP_NO_HEADER_INDEX));
  Require(status == 200);
  std::string body;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  char buffer[8192]; DWORD count;
  do {
    Require(WinHttpReadData(request.get(), buffer, sizeof(buffer), &count));
    Require(body.size() + count <= 8 * 1024 * 1024 && std::chrono::steady_clock::now() < deadline);
    body.append(buffer, count);
  } while (count);
  return body;
}
std::filesystem::path StateRoot() {
  PWSTR value = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &value))) throw std::runtime_error("No update directory");
  std::filesystem::path path(value); CoTaskMemFree(value);
  path /= L"Kelpie"; path /= L"Updates";
  std::filesystem::create_directories(path);
  return path;
}
std::filesystem::path Executable() {
  std::wstring value(32768, 0);
  const auto length = GetModuleFileNameW(nullptr, value.data(), static_cast<DWORD>(value.size()));
  Require(length > 0 && length < value.size()); value.resize(length); return value;
}
}

struct StandaloneUpdates::Impl {
  WindowsApp& app;
  std::wstring arguments;
  std::filesystem::path root = StateRoot(), operation;
  updates::ReleaseMonitor monitor{"windows-x64", KELPIE_APP_VERSION, root / "skipped.json", Fetch};
  HANDLE helper = nullptr;
  HWND progress = nullptr;
  bool busy = false;

  Impl(WindowsApp& browser, std::wstring args) : app(browser), arguments(std::move(args)) {}
  ~Impl() { if (helper) CloseHandle(helper); if (progress && IsWindow(progress)) DestroyWindow(progress); }
  void Error(const std::wstring& message) {
    MessageBoxW(app.window(), message.c_str(), L"Kelpie could not update", MB_OK | MB_ICONERROR);
  }
  void Install(const updates::Release& release) {
    try {
      operation = root / ("update-" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(GetTickCount64()));
      std::filesystem::create_directory(operation);
      const auto exe = Executable();
      std::filesystem::copy_file(exe.parent_path() / "install-update.ps1", operation / "install.ps1");
      const auto path = operation / "request.json";
      std::ofstream output(path);
      output << nlohmann::json{{"url", release.url}, {"sha256", release.sha256}, {"version", release.version},
        {"parent", GetCurrentProcessId()}, {"installDirectory", utf::WideToUtf8(exe.parent_path().wstring()).value()},
        {"profileDirectory", utf::WideToUtf8(app.CurrentSettings().profile_dir).value()},
        {"arguments", utf::WideToUtf8(arguments).value()}}.dump();
      output.close(); Require(bool(output));
      wchar_t system[MAX_PATH]; Require(GetSystemDirectoryW(system, MAX_PATH) > 0);
      const auto powershell = std::filesystem::path(system) / L"WindowsPowerShell/v1.0/powershell.exe";
      std::wstring command = L"\"" + powershell.wstring() + L"\" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" +
          (operation / "install.ps1").wstring() + L"\" -RequestPath \"" + path.wstring() + L"\"";
      STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION process{};
      Require(CreateProcessW(powershell.c_str(), command.data(), nullptr, nullptr, FALSE,
          CREATE_NO_WINDOW, nullptr, operation.c_str(), &startup, &process));
      CloseHandle(process.hThread); helper = process.hProcess; busy = true;
      progress = updates_ui::Progress(app.window());
      // Keep browsing while the helper downloads and validates the complete CEF package.
    } catch (...) { Error(L"The updater could not start. Your current installation is unchanged. Try again after restarting Kelpie."); }
  }
  void Tick() {
    if (busy) {
      std::ifstream status(operation / "status"); std::string value; std::getline(status, value);
      if (value == "ready") { busy = false; app.RequestClose(); return; }
      if (helper && WaitForSingleObject(helper, 0) == WAIT_OBJECT_0) {
        CloseHandle(helper); helper = nullptr; busy = false;
        if (progress) { DestroyWindow(progress); progress = nullptr; }
        Error(L"The update could not be downloaded or verified. Your current installation is unchanged. Try again after restarting Kelpie.");
      }
      return;
    }
    if (!IsWindowVisible(app.window()) || IsIconic(app.window())) return;
    const auto release = monitor.Tick();
    if (!release) return;
    const auto version = utf::Utf8ToWideDisplay(release->version);
    int choice = 102;
    if (FAILED(updates_ui::Prompt(app.window(), version, choice))) { monitor.Retry(*release); return; }
    if (choice == 100) Install(*release);
    if (choice == 101 && !monitor.Skip(*release)) Error(L"Kelpie could not save Skip version. Please try again after restarting the app.");
  }
};
StandaloneUpdates::StandaloneUpdates(WindowsApp& app, std::wstring arguments)
    { try { impl_ = std::make_unique<Impl>(app, std::move(arguments)); } catch (...) {} }
StandaloneUpdates::~StandaloneUpdates() = default;
void StandaloneUpdates::Tick() { if (impl_) impl_->Tick(); }
}
