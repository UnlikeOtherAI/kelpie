#pragma once
#include <filesystem>
#include <string>

namespace kelpie::linuxapp {
class ProfileSession {
 public:
  ~ProfileSession();
  void Open(const std::filesystem::path& directory, const std::string& readiness);
  void Publish(const std::string& id, int port, bool stdio);
  void Clear();
  const std::string& token() const { return token_; }
 private:
  int lock_ = -1;
  std::filesystem::path readiness_;
  std::string token_, launch_;
};
void AtomicWrite(const std::filesystem::path& path, const std::string& contents);
}  // namespace kelpie::linuxapp
