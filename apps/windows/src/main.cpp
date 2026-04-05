#include "windows_app.h"

#include <algorithm>
#include <shellapi.h>

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace kelpie::windows {
namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), '\0');
  if (size > 1) {
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1, nullptr, nullptr);
  }
  return output;
}

std::optional<std::wstring> ReadValue(const std::vector<std::wstring>& args, std::size_t& index) {
  const std::wstring& arg = args[index];
  const auto equals = arg.find(L'=');
  if (equals != std::wstring::npos) {
    return arg.substr(equals + 1);
  }
  if (index + 1 >= args.size()) {
    return std::nullopt;
  }
  ++index;
  return args[index];
}

}  // namespace
}  // namespace kelpie::windows

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show_command) {
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
    if (arg.rfind(L"--port", 0) == 0) {
      if (const auto value = ReadValue(args, i)) {
        config.port = std::max(1, _wtoi(value->c_str()));
        config.port_overridden = true;
      }
    } else if (arg.rfind(L"--profile-dir", 0) == 0) {
      if (const auto value = ReadValue(args, i)) {
        config.profile_dir = std::filesystem::path(*value);
        config.profile_dir_overridden = true;
      }
    } else if (arg.rfind(L"--url", 0) == 0) {
      if (const auto value = ReadValue(args, i)) {
        config.initial_url = WideToUtf8(*value);
        config.url_overridden = true;
      }
    } else if (arg.rfind(L"--width", 0) == 0) {
      if (const auto value = ReadValue(args, i)) {
        config.width = std::max(320, _wtoi(value->c_str()));
        config.width_overridden = true;
      }
    } else if (arg.rfind(L"--height", 0) == 0) {
      if (const auto value = ReadValue(args, i)) {
        config.height = std::max(240, _wtoi(value->c_str()));
        config.height_overridden = true;
      }
    }
  }

  WindowsApp app(instance, std::move(config));
  return app.Run(show_command);
}
