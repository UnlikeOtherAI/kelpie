#include "script_artifact_store.h"
#include "kelpie/base64.h"
#include "kelpie/desktop_script_owner.h"
#include "kelpie/response_helpers.h"
#include <openssl/evp.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <memory>
#include <stdexcept>

namespace kelpie::linuxapp {
namespace {
class Descriptor {
 public:
  explicit Descriptor(int fd) : fd_(fd) {}
  ~Descriptor() { if (fd_ >= 0) close(fd_); }
  operator int() const { return fd_; }
 private:
  int fd_;
};
// Private directories prevent cross-user replacement. Recheck the exact published
// inode before unlinking and preserve already-replaced files and symlinks.
bool Remove(const std::filesystem::path& path, std::uint64_t device, std::uint64_t inode) {
  struct stat info{};
  if (lstat(path.c_str(), &info) != 0) return errno == ENOENT;
  if (!S_ISREG(info.st_mode) || std::uint64_t(info.st_dev) != device ||
      std::uint64_t(info.st_ino) != inode) return true;
  if (unlink(path.c_str()) != 0 && errno != ENOENT) return false;
  std::error_code ignored;
  std::filesystem::remove(path.parent_path(), ignored); // Only succeeds when empty.
  return true;
}
std::string Hash(int fd) {
  std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> digest(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  if (!digest || EVP_DigestInit_ex(digest.get(), EVP_sha256(), nullptr) != 1) throw std::runtime_error("CAPTURE_HASH_FAILED");
  std::array<unsigned char, 65536> bytes{};
  while (true) {
    const auto count = read(fd, bytes.data(), bytes.size());
    if (count < 0 && errno == EINTR) continue;
    if (count < 0) throw std::runtime_error("CAPTURE_HASH_FAILED");
    if (!count) break;
    if (EVP_DigestUpdate(digest.get(), bytes.data(), count) != 1) throw std::runtime_error("CAPTURE_HASH_FAILED");
  }
  std::array<unsigned char, 32> output{}; unsigned length = 0;
  if (EVP_DigestFinal_ex(digest.get(), output.data(), &length) != 1 || length != output.size())
    throw std::runtime_error("CAPTURE_HASH_FAILED");
  constexpr char hex[] = "0123456789abcdef"; std::string result;
  for (const auto byte : output) { result += hex[byte >> 4]; result += hex[byte & 15]; }
  return result;
}
bool Range(const nlohmann::json& body, const char* key) {
  return !body.contains(key) || body[key].is_number_unsigned() ||
         (body[key].is_number_integer() && body[key].get<std::int64_t>() >= 0);
}
}
CaptureFileIdentity InspectCaptureFile(const std::filesystem::path& path) {
  struct stat info{};
  if (lstat(path.c_str(), &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() ||
      (info.st_mode & 077)) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
  return {std::uint64_t(info.st_dev), std::uint64_t(info.st_ino)};
}
bool RemoveCaptureFile(const std::filesystem::path& path, const CaptureFileIdentity& identity) {
  return Remove(path, identity.device, identity.inode);
}
std::filesystem::path CreatePrivateCaptureDirectory() {
  auto pattern = (std::filesystem::temp_directory_path() / "kelpie-capture-XXXXXX").string();
  if (!mkdtemp(pattern.data())) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
  if (chmod(pattern.c_str(), 0700) != 0) { rmdir(pattern.c_str()); throw std::runtime_error("CAPTURE_STORAGE_FAILED"); }
  // The atomically created directory is private before any capture bytes exist.
  return pattern;
}
void WriteCaptureFile(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes) {
  Descriptor fd(open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
  if (fd < 0) throw std::runtime_error(errno == EEXIST ? "CAPTURE_OUTPUT_EXISTS" : "CAPTURE_OUTPUT_UNAVAILABLE");
  bool valid = true; std::size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count = write(fd, bytes.data() + offset, bytes.size() - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) { valid = false; break; }
    offset += std::size_t(count);
  }
  if (fsync(fd) != 0) valid = false;
  if (!valid) { unlink(path.c_str()); throw std::runtime_error("CAPTURE_OUTPUT_UNAVAILABLE"); }
}
ScriptArtifactStore::~ScriptArtifactStore() {
  for (const auto& [id, entry] : entries_) Remove(entry.path, entry.device, entry.inode);
}
ScriptArtifactStore::Json ScriptArtifactStore::Publish(const std::filesystem::path& path,
    const std::string& mime, Json metadata, const std::string& run, const std::string& owner) {
  if (owner.empty() || run.empty()) throw std::runtime_error("CAPTURE_AUTHORIZATION_REVOKED");
  Descriptor fd(open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)); struct stat info{};
  if (fd < 0 || fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() ||
      (info.st_mode & 077) || info.st_size <= 0 || std::uint64_t(info.st_size) > 268435456)
    throw std::runtime_error("CAPTURE_STORAGE_FAILED");
  metadata["id"] = NewDesktopScriptId(); metadata["mimeType"] = mime; metadata["byteLength"] = info.st_size;
  metadata["sha256"] = Hash(fd); if (!metadata.contains("partial")) metadata["partial"] = false;
  std::lock_guard lock(mutex_); Expire(std::uint64_t(info.st_size));
  std::uint64_t retained = 0;
  for (const auto& [id, entry] : entries_) retained += entry.manifest.value("byteLength", std::uint64_t(0));
  if (entries_.size() >= 4096 || retained > 268435456 - std::uint64_t(info.st_size))
    throw std::runtime_error("CAPTURE_STORAGE_FULL");
  entries_.emplace(metadata["id"].get<std::string>(), Entry{path, run, owner, metadata,
      std::chrono::steady_clock::now(), std::uint64_t(info.st_dev), std::uint64_t(info.st_ino)});
  Expire(); return metadata;
}
void ScriptArtifactStore::Expire(std::uint64_t reserve) {
  const auto now = std::chrono::steady_clock::now();
  for (auto it = entries_.begin(); it != entries_.end();) {
    if (it->second.revoked || now - it->second.created >= std::chrono::hours(1)) {
      it->second.revoked = true;
      if (Remove(it->second.path, it->second.device, it->second.inode)) it = entries_.erase(it);
      else ++it; // Keep failed deletion owned for another cleanup attempt.
    } else ++it;
  }
  std::uint64_t total = 0;
  for (const auto& [id, entry] : entries_) total += entry.manifest.value("byteLength", std::uint64_t(0));
  while ((total > 268435456 - reserve || entries_.size() + (reserve != 0) > 4096) && !entries_.empty()) {
    auto oldest = std::min_element(entries_.begin(), entries_.end(), [](const auto& a, const auto& b) { return a.second.created < b.second.created; });
    total -= oldest->second.manifest.value("byteLength", std::uint64_t(0));
    oldest->second.revoked = true;
    if (!Remove(oldest->second.path, oldest->second.device, oldest->second.inode)) break;
    entries_.erase(oldest);
  }
}
void ScriptArtifactStore::Discard(const std::string& run, const std::string& owner) {
  if (run.empty() || owner.empty()) throw std::runtime_error("CAPTURE_AUTHORIZATION_REVOKED");
  std::lock_guard lock(mutex_);
  bool failed = false;
  for (auto it = entries_.begin(); it != entries_.end();) {
    auto& entry = it->second;
    if (entry.run != run || entry.owner != owner) { ++it; continue; }
    entry.revoked = true; // Revoke access even if physical cleanup must retry.
    if (Remove(entry.path, entry.device, entry.inode)) it = entries_.erase(it);
    else { failed = true; ++it; }
  }
  if (failed) throw std::runtime_error("CAPTURE_DISCARD_FAILED");
}
ScriptArtifactStore::Json ScriptArtifactStore::Read(const Json& body, const std::string& owner) {
  if (!body.is_object() || !body.contains("runId") || !body["runId"].is_string() ||
      !body.contains("artifactId") || !body["artifactId"].is_string())
    return ErrorResponse("INVALID_PARAMS", "Run and artifact IDs are required");
  for (const auto& field : body.items())
    if (field.key() != "runId" && field.key() != "artifactId" && field.key() != "offset" && field.key() != "length")
      return ErrorResponse("INVALID_PARAMS", "Unknown artifact range field");
  const auto run = body["runId"].get<std::string>(), id = body["artifactId"].get<std::string>();
  if (run.empty() || id.empty() || run.size() > 128 || id.size() > 128 || !Range(body, "offset") || !Range(body, "length"))
    return ErrorResponse("INVALID_PARAMS", "Artifact IDs or ranges exceed their limits");
  const auto offset = body.value("offset", std::uint64_t(0)), length = body.value("length", std::uint64_t(262144));
  if (!length || length > 1048576) return ErrorResponse("INVALID_PARAMS", "Artifact chunk exceeds range limit");
  std::lock_guard lock(mutex_); Expire(); const auto found = entries_.find(id);
  if (owner.empty() || found == entries_.end() || found->second.run != run || found->second.owner != owner || found->second.revoked)
    return ErrorResponse("ARTIFACT_NOT_FOUND", "Artifact expired or is not owned by this grant");
  const auto& entry = found->second; const auto total = entry.manifest["byteLength"].get<std::uint64_t>();
  if (offset > total) return ErrorResponse("INVALID_PARAMS", "Artifact offset is beyond end");
  Descriptor fd(open(entry.path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)); struct stat info{};
  if (fd < 0 || fstat(fd, &info) || !S_ISREG(info.st_mode) || std::uint64_t(info.st_dev) != entry.device ||
      std::uint64_t(info.st_ino) != entry.inode || info.st_size < 0 || std::uint64_t(info.st_size) != total)
    return ErrorResponse("ARTIFACT_READ_FAILED", "Artifact chunk could not be read");
  std::vector<std::uint8_t> bytes(std::min(length, total - offset)); std::size_t done = 0;
  while (done < bytes.size()) {
    const auto count = pread(fd, bytes.data() + done, bytes.size() - done, off_t(offset + done));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return ErrorResponse("ARTIFACT_READ_FAILED", "Artifact chunk could not be read");
    done += std::size_t(count);
  }
  return SuccessResponse({{"runId", run}, {"artifactId", id}, {"data", Base64Encode(bytes)}, {"offset", offset},
      {"nextOffset", offset + bytes.size()}, {"eof", offset + bytes.size() == total},
      {"mimeType", entry.manifest["mimeType"]}, {"byteLength", total}, {"sha256", entry.manifest["sha256"]}});
}
}
