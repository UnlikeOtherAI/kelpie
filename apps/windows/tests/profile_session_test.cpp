#include "profile_session.h"

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <string>

#include <nlohmann/json.hpp>
#include <sddl.h>

namespace {

using kelpie::windows::ProfileSession;

std::filesystem::path UniqueTestPath() {
  // CTest runs from the task build directory, so profile state remains inside
  // this worktree instead of the user's shared TEMP or application profile.
  wchar_t directory[MAX_PATH]{};
  if (GetCurrentDirectoryW(MAX_PATH, directory) == 0) return {};
  wchar_t name[MAX_PATH]{};
  if (GetTempFileNameW(directory, L"kel", 0, name) == 0) return {};
  DeleteFileW(name);
  return std::filesystem::path(name);
}

std::string ReadLaunchId(const std::filesystem::path& readiness) {
  std::ifstream input(readiness);
  nlohmann::json record;
  input >> record;
  return record.value("launchId", "");
}

int LeaveReadiness(const std::filesystem::path& profile) {
  ProfileSession session;
  std::string error;
  if (!session.Open(profile, {}, &error) ||
      !session.PublishReadiness("device-test", 8420, false, &error)) {
    return 10;
  }
  // Model an abrupt process exit. The parent test verifies that a subsequent
  // exclusive profile owner can replace this protected record.
  TerminateProcess(GetCurrentProcess(), 0);
  return 11;
}

bool RunAbandoningChild(const std::filesystem::path& profile) {
  wchar_t executable[MAX_PATH]{};
  if (GetModuleFileNameW(nullptr, executable, MAX_PATH) == 0) return false;
  const std::wstring command = L"\"" + std::wstring(executable) + L"\" --leave-readiness \"" +
                               profile.wstring() + L"\"";
  std::wstring mutable_command = command;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr,
                      &startup, &child)) {
    return false;
  }
  const DWORD wait = WaitForSingleObject(child.hProcess, 10'000);
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  return wait == WAIT_OBJECT_0;
}

bool LegacyOpenThenPublish(const std::filesystem::path& profile,
                           const std::filesystem::path& readiness) {
  const HANDLE lock = CreateFileW((profile / L"profile.lock").c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr);
  if (lock == INVALID_HANDLE_VALUE) return false;
  const std::filesystem::path temporary = readiness.wstring() + L".legacy.tmp";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  const bool descriptor_created = ConvertStringSecurityDescriptorToSecurityDescriptorW(
      L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;OW)", SDDL_REVISION_1, &descriptor, nullptr) != FALSE;
  SECURITY_ATTRIBUTES attributes{};
  attributes.nLength = sizeof(attributes);
  attributes.lpSecurityDescriptor = descriptor;
  const HANDLE file = descriptor_created
      ? CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, &attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr)
      : INVALID_HANDLE_VALUE;
  if (descriptor != nullptr) LocalFree(descriptor);
  if (file == INVALID_HANDLE_VALUE) {
    CloseHandle(lock);
    return false;
  }
  const std::string record = R"({"version":1,"launchId":"legacy-replacement","token":"redacted"})";
  DWORD written = 0;
  const bool written_fully = WriteFile(file, record.data(), static_cast<DWORD>(record.size()), &written, nullptr) != FALSE &&
      written == record.size() && FlushFileBuffers(file) != FALSE;
  CloseHandle(file);
  const bool replaced = written_fully &&
      MoveFileExW(temporary.c_str(), readiness.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != FALSE;
  if (!replaced) DeleteFileW(temporary.c_str());
  CloseHandle(lock);
  return replaced;
}

void RemoveTree(const std::filesystem::path& path) {
  std::error_code error;
  std::filesystem::remove_all(path, error);
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc == 3 && std::wstring_view(argv[1]) == L"--leave-readiness") {
    return LeaveReadiness(argv[2]);
  }

  const std::filesystem::path root = UniqueTestPath();
  if (root.empty()) return 1;
  const std::filesystem::path profile = root / L"profile";
  const std::filesystem::path readiness = profile / L"readiness.json";
  if (!RunAbandoningChild(profile) || !std::filesystem::exists(readiness)) {
    RemoveTree(root);
    return 2;
  }
  const std::string stale_launch_id = ReadLaunchId(readiness);
  if (stale_launch_id.empty()) {
    RemoveTree(root);
    return 3;
  }
  // This is the protected-file replacement sequence from the previous
  // implementation. It establishes that the sequence itself works for an
  // abruptly abandoned record; it does not identify a separate runtime stage
  // failure in a live launch.
  if (!LegacyOpenThenPublish(profile, readiness) || ReadLaunchId(readiness) != "legacy-replacement") {
    RemoveTree(root);
    return 4;
  }
  if (!RunAbandoningChild(profile) || !std::filesystem::exists(readiness)) {
    RemoveTree(root);
    return 5;
  }

  {
    ProfileSession replacement;
    std::string error;
    if (!replacement.Open(profile, {}, &error)) {
      RemoveTree(root);
      return 6;
    }
    // The stale record disappears as soon as this process has the exclusive
    // profile handle, before it opens a listener or publishes its capability.
    if (std::filesystem::exists(readiness)) {
      RemoveTree(root);
      return 7;
    }
    if (!replacement.PublishReadiness("device-test", 8420, false, &error)) {
      RemoveTree(root);
      return 8;
    }
    const std::string fresh_launch_id = ReadLaunchId(readiness);
    if (fresh_launch_id.empty() || fresh_launch_id == stale_launch_id) {
      RemoveTree(root);
      return 9;
    }
  }
  if (std::filesystem::exists(readiness)) {
    RemoveTree(root);
    return 10;
  }

  const std::filesystem::path invalid_readiness = profile / L"not-a-readiness-file";
  std::filesystem::create_directories(invalid_readiness);
  {
    ProfileSession failed_publish;
    std::string error;
    if (failed_publish.Open(profile, invalid_readiness, &error) || error.empty()) {
      RemoveTree(root);
      return 11;
    }
  }
  bool lock_released = false;
  {
    ProfileSession lock_check;
    std::string error;
    lock_released = lock_check.Open(profile, {}, &error);
  }
  RemoveTree(root);
  return lock_released ? 0 : 12;
}
