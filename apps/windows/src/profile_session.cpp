#include "profile_session.h"

#include <algorithm>
#include <array>
#include <fstream>
#include <sstream>

#include <windows.h>
#include <bcrypt.h>
#include <sddl.h>

#include <nlohmann/json.hpp>

namespace kelpie::windows {
namespace {

void SetError(std::string* error, std::string message) {
  if (error != nullptr) *error = std::move(message);
}

std::string Hex(const std::array<unsigned char, 32>& bytes) {
  constexpr char kDigits[] = "0123456789abcdef";
  std::string value;
  value.reserve(bytes.size() * 2);
  for (const unsigned char byte : bytes) {
    value.push_back(kDigits[byte >> 4]);
    value.push_back(kDigits[byte & 0x0f]);
  }
  return value;
}

std::string RandomHex() {
  std::array<unsigned char, 32> bytes{};
  return BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()),
                         BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0
             ? Hex(bytes)
             : std::string();
}

std::wstring Wide(const std::filesystem::path& path) {
  return path.wstring();
}

std::string ReadText(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  std::ostringstream output;
  output << input.rdbuf();
  return output.str();
}

// With long paths off (the Windows default), a path is limited to MAX_PATH
// including its terminating NUL, and the app's longPathAware manifest entry
// does nothing. A failure on such a path says so, because "unable to write"
// alone sends people looking for a permissions problem.
std::string WithPathLimit(std::string message, std::size_t length) {
  if (length < MAX_PATH) return message;
  return message + ": its path is " + std::to_string(length) +
         " characters, and Windows allows at most " + std::to_string(MAX_PATH - 1) +
         " unless long paths are enabled. Use a shorter --profile-dir or --readiness-file";
}

}  // namespace

std::filesystem::path ReadinessTemporaryPath(const std::filesystem::path& readiness_path,
                                             const std::string& launch_id) {
  // A sibling named "~<8 hex>.tmp" is 13 characters, shorter than
  // "readiness.json", so whenever the final path fits under MAX_PATH the
  // temporary one does too. Appending the full 64-hex launch id to the record's
  // own name added 69 characters and broke profiles near the limit. Eight hex
  // digits still keep two launches apart when they share a --readiness-file
  // directory; the profile lock already serialises launches of one profile.
  const std::string suffix = launch_id.substr(0, 8);
  return readiness_path.parent_path() /
         (L"~" + std::wstring(suffix.begin(), suffix.end()) + L".tmp");
}

ProfileSession::~ProfileSession() {
  ClearReadiness();
  if (lock_handle_ != nullptr) {
    CloseHandle(static_cast<HANDLE>(lock_handle_));
  }
}

bool ProfileSession::Open(const std::filesystem::path& profile_dir,
                          const std::filesystem::path& readiness_path,
                          std::string* error) {
  std::error_code filesystem_error;
  std::filesystem::create_directories(profile_dir, filesystem_error);
  if (filesystem_error) {
    SetError(error, "Unable to create the profile directory");
    return false;
  }

  const std::filesystem::path lock_path = profile_dir / "profile.lock";
  HANDLE handle = CreateFileW(Wide(lock_path).c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    // Only a sharing violation means another launch holds the lock. A lock path
    // past MAX_PATH fails differently, and calling that "in use" hid the limit.
    SetError(error, GetLastError() == ERROR_SHARING_VIOLATION
                        ? std::string("This profile is already in use")
                        : WithPathLimit("Unable to open the profile lock", lock_path.native().size()));
    return false;
  }

  token_ = RandomHex();
  launch_id_ = RandomHex();
  if (token_.empty() || launch_id_.empty()) {
    CloseHandle(handle);
    SetError(error, "Windows could not generate a control capability");
    return false;
  }
  lock_handle_ = handle;
  readiness_path_ = readiness_path.empty() ? profile_dir / "readiness.json" : readiness_path;
  // The exclusive profile handle proves this process owns the profile. A
  // predecessor may have crashed after publishing a capability; it must never
  // remain discoverable while this launch is still starting.
  if (!RemoveStaleReadiness(error)) {
    CloseHandle(handle);
    lock_handle_ = nullptr;
    token_.clear();
    launch_id_.clear();
    readiness_path_.clear();
    return false;
  }
  return true;
}

bool ProfileSession::PublishReadiness(const std::string& device_id,
                                      int port,
                                      bool stdio_mcp,
                                      std::string* error) {
  const nlohmann::json record = {
      {"version", 1},
      {"launchId", launch_id_},
      {"deviceId", device_id},
      {"port", port},
      {"token", token_},
      {"controlMode", "loopback"},
      {"mcp", {{"http", true}, {"stdio", stdio_mcp}, {"endpoint", "/mcp"}}},
  };
  const std::filesystem::path temporary = ReadinessTemporaryPath(readiness_path_, launch_id_);
  // The record's own path is the one a caller chose, so the limit hint quotes
  // it; the temporary sibling is only longer for an unusually short custom name.
  const std::size_t longest = (std::max)(readiness_path_.native().size(), temporary.native().size());
  if (!WriteProtectedFile(temporary, record.dump(), error)) {
    if (error != nullptr) *error = WithPathLimit(std::move(*error), longest);
    return false;
  }
  if (!MoveFileExW(Wide(temporary).c_str(), Wide(readiness_path_).c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(Wide(temporary).c_str());
    SetError(error, WithPathLimit("Unable to publish the readiness record", longest));
    return false;
  }
  return true;
}

void ProfileSession::ClearReadiness() {
  if (readiness_path_.empty() || launch_id_.empty()) {
    return;
  }
  const nlohmann::json record = nlohmann::json::parse(ReadText(readiness_path_), nullptr, false);
  const auto launch_id = record.is_object() ? record.find("launchId") : record.end();
  if (launch_id == record.end() || !launch_id->is_string() || launch_id->get<std::string>() != launch_id_) {
    return;
  }
  DeleteFileW(Wide(readiness_path_).c_str());
}

bool ProfileSession::RemoveStaleReadiness(std::string* error) const {
  // The error_code overload: a path past MAX_PATH makes the throwing one raise,
  // which would abort startup instead of reaching the publish step and its
  // explanation of the limit.
  std::error_code filesystem_error;
  if (readiness_path_.empty() || !std::filesystem::exists(readiness_path_, filesystem_error)) {
    return true;
  }
  if (DeleteFileW(Wide(readiness_path_).c_str()) != FALSE ||
      GetLastError() == ERROR_FILE_NOT_FOUND) {
    return true;
  }
  SetError(error, "Unable to remove the stale readiness record");
  return false;
}

bool ProfileSession::WriteProtectedFile(const std::filesystem::path& path,
                                        const std::string& contents,
                                        std::string* error) const {
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;OW)", SDDL_REVISION_1, &descriptor, nullptr)) {
    SetError(error, "Unable to protect the readiness record");
    return false;
  }
  SECURITY_ATTRIBUTES attributes{};
  attributes.nLength = sizeof(attributes);
  attributes.lpSecurityDescriptor = descriptor;
  HANDLE file = CreateFileW(Wide(path).c_str(), GENERIC_WRITE, 0, &attributes, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_HIDDEN, nullptr);
  LocalFree(descriptor);
  if (file == INVALID_HANDLE_VALUE) {
    SetError(error, "Unable to write the readiness record");
    return false;
  }
  DWORD written = 0;
  const bool complete = WriteFile(file, contents.data(), static_cast<DWORD>(contents.size()), &written,
                                  nullptr) != FALSE && written == contents.size() && FlushFileBuffers(file) != FALSE;
  CloseHandle(file);
  if (!complete) {
    DeleteFileW(Wide(path).c_str());
    SetError(error, "Unable to flush the readiness record");
  }
  return complete;
}

}  // namespace kelpie::windows
