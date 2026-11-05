#pragma once
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <map>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace kelpie::linuxapp {
struct CaptureFileIdentity { std::uint64_t device = 0, inode = 0; };
CaptureFileIdentity InspectCaptureFile(const std::filesystem::path& path);
bool RemoveCaptureFile(const std::filesystem::path& path, const CaptureFileIdentity& identity);
std::filesystem::path CreatePrivateCaptureDirectory();
void WriteCaptureFile(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes);
class ScriptArtifactStore {
 public:
  using Json = nlohmann::json;
  ~ScriptArtifactStore();
  Json Publish(const std::filesystem::path& path, const std::string& mime, Json metadata,
               const std::string& run, const std::string& owner);
  Json Read(const Json& request, const std::string& owner);
  void Discard(const std::string& run, const std::string& owner);
 private:
  struct Entry {
    std::filesystem::path path;
    std::string run, owner;
    Json manifest;
    std::chrono::steady_clock::time_point created;
    std::uint64_t device = 0, inode = 0;
    bool revoked = false;
  };
  void Expire(std::uint64_t reserve = 0);
  std::mutex mutex_;
  std::map<std::string, Entry> entries_;
};
}
