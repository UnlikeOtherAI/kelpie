#include "windows_app.h"
#include "windows_utf.h"

#if defined(HAS_CEF)
#include "include/cef_sandbox_win.h"
#include "include/cef_app.h"
#include "kelpie/cef_app_factory.h"
#include <cstring>
#endif

#include <algorithm>
#include <shellapi.h>

#include <filesystem>
#include <limits>
#include <optional>
#include <string>
#include <vector>

namespace kelpie::windows {
namespace {

bool IsOption(const std::wstring& arg, const std::wstring& option) {
  return arg == option || (arg.size() > option.size() && arg.starts_with(option + L"="));
}

std::optional<std::wstring> ReadValue(const std::vector<std::wstring>& args,
                                      std::size_t& index,
                                      const std::wstring& option) {
  const std::wstring& arg = args[index];
  if (!IsOption(arg, option)) return std::nullopt;
  if (arg.size() > option.size()) {
    const std::wstring value = arg.substr(option.size() + 1);
    return value.empty() ? std::nullopt : std::optional(value);
  }
  if (index + 1 >= args.size()) {
    return std::nullopt;
  }
  ++index;
  return args[index];
}

std::optional<int> ParseInt(const std::wstring& value, int minimum, int maximum) {
  if (value.empty()) return std::nullopt;
  wchar_t* end = nullptr;
  const long parsed = wcstol(value.c_str(), &end, 10);
  if (end == value.c_str() || *end != L'\0' || parsed < minimum || parsed > maximum) return std::nullopt;
  return static_cast<int>(parsed);
}

bool IsRejectedBrowserSwitch(const std::wstring& arg) {
  static constexpr std::wstring_view blocked[] = {
      L"--no-sandbox", L"--disable-gpu-sandbox", L"--single-process", L"--in-process-gpu",
      L"--remote-debugging-port", L"--remote-debugging-address"};
  for (const auto switch_name : blocked) {
    if (arg == switch_name || arg.starts_with(std::wstring(switch_name) + L"=")) return true;
  }
  return false;
}

}  // namespace
}  // namespace kelpie::windows

int RunKelpieWindowsApp(HINSTANCE resource_instance,
                        HINSTANCE cef_process_instance,
                        PWSTR command_line,
                        int show_command,
                        void* sandbox_info) {
  using namespace kelpie::windows;

  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::vector<std::wstring> args;
  if (argv != nullptr) {
    args.assign(argv, argv + argc);
    LocalFree(argv);
  }

  AppConfig config;
  for (std::size_t i = 1; i < args.size(); ++i) {
    const std::wstring& arg = args[i];
    if (IsRejectedBrowserSwitch(arg)) return ERROR_ACCESS_DENIED;
    if (IsOption(arg, L"--port")) {
      const auto value = ReadValue(args, i, L"--port");
      const auto port = value ? ParseInt(*value, 1, 65535) : std::nullopt;
      if (!port) return ERROR_INVALID_PARAMETER;
      config.port = *port;
      config.port_overridden = true;
    } else if (IsOption(arg, L"--profile-dir")) {
      const auto value = ReadValue(args, i, L"--profile-dir");
      if (!value || !std::filesystem::path(*value).is_absolute()) return ERROR_INVALID_PARAMETER;
      config.profile_dir = std::filesystem::path(*value);
      config.profile_dir_overridden = true;
    } else if (IsOption(arg, L"--readiness-file")) {
      const auto value = ReadValue(args, i, L"--readiness-file");
      if (!value || !std::filesystem::path(*value).is_absolute()) return ERROR_INVALID_PARAMETER;
      config.readiness_path = std::filesystem::path(*value);
    } else if (arg == L"--mcp-stdio") {
      // The Windows app exposes authenticated loopback HTTP. The CLI owns the
      // stdio bridge so the GUI never starts a second blocking stdin reader.
      return ERROR_NOT_SUPPORTED;
    } else if (IsOption(arg, L"--url")) {
      const auto value = ReadValue(args, i, L"--url");
      const auto utf8 = value ? utf::WideToUtf8(*value) : std::nullopt;
      if (!utf8 || utf8->empty()) return ERROR_INVALID_PARAMETER;
      config.initial_url = *utf8;
      config.url_overridden = true;
    } else if (IsOption(arg, L"--width")) {
      const auto value = ReadValue(args, i, L"--width");
      const auto width = value ? ParseInt(*value, 320, 16384) : std::nullopt;
      if (!width) return ERROR_INVALID_PARAMETER;
      config.width = *width;
      config.width_overridden = true;
    } else if (IsOption(arg, L"--height")) {
      const auto value = ReadValue(args, i, L"--height");
      const auto height = value ? ParseInt(*value, 240, 16384) : std::nullopt;
      if (!height) return ERROR_INVALID_PARAMETER;
      config.height = *height;
      config.height_overridden = true;
    }
    else if (arg.starts_with(L"--")) {
      // Do not forward arbitrary Chromium switches through the authenticated
      // desktop launcher. Subprocess switches have already been consumed by
      // CefExecuteProcess above.
      return ERROR_INVALID_PARAMETER;
    }
  }

  config.sandbox_info = sandbox_info;
  config.cef_process_instance = cef_process_instance;
  WindowsApp app(resource_instance, std::move(config));
  return app.Run(show_command);
}

#if defined(HAS_CEF)
// The sandboxed CEF bootstrap resolves this with GetProcAddress, and `extern
// "C"` only settles the name mangling — without dllexport the symbol is absent
// from the DLL and the shipped launcher cannot start the app.
extern "C" __declspec(dllexport) int RunWinMain(HINSTANCE instance,
                            LPWSTR command_line,
                            int show_command,
                            void* sandbox_info,
                            cef_version_info_t* version_info) {
  if (version_info == nullptr || version_info->size < CEF_VERSION_INFO_SIZE_WITH_SANDBOX_HASH) {
    return ERROR_REVISION_MISMATCH;
  }
  cef_version_info_t expected{};
  CEF_POPULATE_VERSION_INFO(&expected);
  if (version_info->cef_version_major != expected.cef_version_major ||
      version_info->cef_version_minor != expected.cef_version_minor ||
      version_info->cef_version_patch != expected.cef_version_patch ||
      std::strncmp(version_info->sandbox_compat_hash, expected.sandbox_compat_hash,
                   sizeof(expected.sandbox_compat_hash)) != 0) {
    return ERROR_REVISION_MISMATCH;
  }
  CefMainArgs main_args(instance);
  CefRefPtr<CefApp> app = kelpie::CreateDesktopCefApp();
  const int subprocess_exit = CefExecuteProcess(main_args, app, sandbox_info);
  if (subprocess_exit >= 0) return subprocess_exit;
  HMODULE client_module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(&RunWinMain), &client_module)) {
    return GetLastError();
  }
  return RunKelpieWindowsApp(client_module, instance, command_line, show_command, sandbox_info);
}
#else
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR command_line, int show_command) {
  return RunKelpieWindowsApp(instance, instance, command_line, show_command, nullptr);
}
#endif
