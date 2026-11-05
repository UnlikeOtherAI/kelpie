#include "kelpie/peer_trust.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace kelpie {
namespace {
using Json = nlohmann::json;
class CorruptTrustStore : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};
Json EmptyStore() { return {{"version", 1}, {"generation", 0}, {"computers", Json::array()}}; }

class StoreLock {
 public:
  explicit StoreLock(const std::filesystem::path& path) {
    if (path.empty()) throw std::runtime_error("Trust storage unavailable");
    std::filesystem::create_directories(path.parent_path());
    auto lock_path = path;
    lock_path += ".lock";
#ifdef _WIN32
    handle_ = CreateFileW(lock_path.c_str(), GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    OVERLAPPED overlap{};
    if (handle_ == INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot open trust lock");
    if (!LockFileEx(handle_, LOCKFILE_EXCLUSIVE_LOCK, 0, 1, 0, &overlap)) {
      CloseHandle(handle_); throw std::runtime_error("Cannot lock trust storage");
    }
#else
    fd_ = open(lock_path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd_ < 0) throw std::runtime_error("Cannot open trust lock");
    if (flock(fd_, LOCK_EX) != 0) { close(fd_); throw std::runtime_error("Cannot lock trust storage"); }
#endif
  }
  ~StoreLock() {
#ifdef _WIN32
    OVERLAPPED overlap{};
    UnlockFileEx(handle_, 0, 1, 0, &overlap); CloseHandle(handle_);
#else
    flock(fd_, LOCK_UN); close(fd_);
#endif
  }
  StoreLock(const StoreLock&) = delete;
  StoreLock& operator=(const StoreLock&) = delete;
 private:
#ifdef _WIN32
  HANDLE handle_ = INVALID_HANDLE_VALUE;
#else
  int fd_ = -1;
#endif
};

Json Read(const std::filesystem::path& path) {
  if (!std::filesystem::exists(path)) return EmptyStore();
  if (std::filesystem::file_size(path) > 1024 * 1024) throw CorruptTrustStore("Trust storage is too large");
  std::ifstream file(path, std::ios::binary);
  if (!file) throw std::runtime_error("Cannot read trust storage");
  try {
    auto data = Json::parse(file);
    if (!data.is_object() || !data.contains("version") || !data["version"].is_number_integer())
      throw CorruptTrustStore("Invalid trust storage");
    // An older app must not replace a valid newer schema during a downgrade.
    if (data["version"] != 1) throw std::runtime_error("Unsupported trust storage version");
    if (!data.contains("computers") || !data["computers"].is_array() || data["computers"].size() > 256)
      throw CorruptTrustStore("Invalid trust storage");
    for (const auto& row : data["computers"]) {
      const auto address = row.at("address").get<std::string>();
      if (CanonicalPeerAddress(address) != std::optional<std::string>(address) ||
          !row.at("name").is_string() || !row.at("approvedAt").is_number())
        throw CorruptTrustStore("Invalid trusted computer");
    }
    return data;
  } catch (const Json::exception&) { throw CorruptTrustStore("Invalid trust storage JSON"); }
}

void Write(const std::filesystem::path& path, Json data) {
  data["generation"] = data.value("generation", std::uint64_t(0)) + 1;
  const std::string bytes = data.dump();
  auto temporary = path;
  temporary += ".tmp";
#ifdef _WIN32
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot write trust storage");
  DWORD written = 0;
  const bool saved = WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) &&
      written == bytes.size() && FlushFileBuffers(file);
  CloseHandle(file);
  if (!saved || !MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    throw std::runtime_error("Cannot persist trust storage");
#else
  const int file = open(temporary.c_str(), O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (file < 0) throw std::runtime_error("Cannot write trust storage");
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count = write(file, bytes.data() + offset, bytes.size() - offset);
    if (count <= 0) { close(file); throw std::runtime_error("Cannot write trust storage"); }
    offset += static_cast<std::size_t>(count);
  }
  const bool saved = fchmod(file, 0600) == 0 && fsync(file) == 0;
  close(file);
  if (!saved || rename(temporary.c_str(), path.c_str()) != 0) throw std::runtime_error("Cannot persist trust storage");
  const int directory = open(path.parent_path().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (directory < 0) throw std::runtime_error("Cannot sync trust directory");
  const bool synced = fsync(directory) == 0;
  close(directory);
  if (!synced) throw std::runtime_error("Cannot sync trust directory");
#endif
}

std::string Address(const std::string& input) {
  const auto address = CanonicalPeerAddress(input);
  if (!address) throw std::runtime_error("Invalid socket address");
  return *address;
}
}  // namespace

PeerTrustStore::PeerTrustStore(std::filesystem::path path) : path_(std::move(path)) {}

std::string SanitizePeerLabel(const std::string& input) {
  std::size_t end = std::min<std::size_t>(input.size(), 256);
  // JSON input is UTF-8. Never split a multibyte character at the display limit.
  if (end < input.size()) while (end > 0 && (static_cast<unsigned char>(input[end]) & 0xc0) == 0x80) --end;
  std::string label = input.substr(0, end);
  label.erase(std::remove_if(label.begin(), label.end(), [](unsigned char c) { return c < 32 || c == 127; }), label.end());
  return label;
}

std::filesystem::path PeerTrustStore::DefaultPath() {
#ifdef _WIN32
  const auto size = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (size == 0) return {};
  std::wstring base(size, L'\0');
  const auto length = GetEnvironmentVariableW(L"LOCALAPPDATA", base.data(), size);
  if (length == 0 || length >= size) return {};
  base.resize(length);
  return std::filesystem::path(base) / L"Kelpie" / L"trusted-computers.json";
#else
  const auto config = std::getenv("XDG_CONFIG_HOME");
  const auto home = std::getenv("HOME");
  if (config && *config) return std::filesystem::path(config) / "kelpie" / "trusted-computers.json";
  return home ? std::filesystem::path(home) / ".config" / "kelpie" / "trusted-computers.json" : std::filesystem::path();
#endif
}

Json PeerTrustStore::List() const {
  const StoreLock lock(path_);
  return Read(path_)["computers"];
}

bool PeerTrustStore::IsTrusted(const std::string& input) const {
  if (IsLoopbackPeer(input)) return true;
  const auto address = CanonicalPeerAddress(input);
  if (!address) return false;
  try {
    for (const auto& row : List()) if (row["address"] == *address) return true;
  } catch (...) { /* A broken or removed store never grants remote authority. */ }
  return false;
}

void PeerTrustStore::Approve(const std::string& input, const std::string& name) {
  const auto address = Address(input);
  if (IsLoopbackPeer(address)) return;
  const StoreLock lock(path_);
  Json data;
  try { data = Read(path_); }
  catch (const CorruptTrustStore&) {
    // Only a fresh explicit approval can recover a corrupt store. Preserve the
    // original evidence and grant only the address the user just approved.
    auto archive = path_;
    archive += ".corrupt-" + PeerRequestNonce();
    std::filesystem::rename(path_, archive);
    data = EmptyStore();
  }
  auto& rows = data["computers"];
  for (const auto& row : rows) if (row["address"] == address) return;
  if (rows.size() >= 256) throw std::runtime_error("Trusted computer limit reached");
  const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
  rows.push_back({{"address", address}, {"name", SanitizePeerLabel(name)}, {"approvedAt", now}});
  Write(path_, std::move(data));
}

void PeerTrustStore::Revoke(const std::string& input) {
  const auto address = Address(input);
  const StoreLock lock(path_);
  auto data = Read(path_);
  auto& rows = data["computers"];
  rows.erase(std::remove_if(rows.begin(), rows.end(), [&](const Json& row) { return row["address"] == address; }), rows.end());
  Write(path_, std::move(data));
}
}  // namespace kelpie
