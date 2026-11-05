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
std::filesystem::path CreatePrivateCaptureDirectory();
void WriteCaptureFile(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes);
class ScriptArtifactStore {
 public:
  using Json = nlohmann::json;
  ~ScriptArtifactStore();
  Json Publish(const std::filesystem::path& path, const std::string& mime, Json metadata,
               const std::string& run, const std::string& owner);
  Json Read(const Json& request, const std::string& owner);
 private:
  struct Entry {
    std::filesystem::path path;
    std::string run, owner;
    Json manifest;
    std::chrono::steady_clock::time_point created;
    std::uint64_t device = 0, inode = 0;
  };
  void Expire();
  std::mutex mutex_;
  std::map<std::string, Entry> entries_;
};
}
