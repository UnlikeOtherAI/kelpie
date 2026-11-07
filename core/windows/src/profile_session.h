#pragma once

#include <filesystem>
#include <string>

namespace kelpie::windows {

class ProfileSession {
 public:
  ProfileSession() = default;
  ~ProfileSession();

  ProfileSession(const ProfileSession&) = delete;
  ProfileSession& operator=(const ProfileSession&) = delete;

  bool Open(const std::filesystem::path& profile_dir,
            const std::filesystem::path& readiness_path,
            std::string* error);
  bool PublishReadiness(const std::string& device_id,
                        int port,
                        bool stdio_mcp,
                        std::string* error);
  void ClearReadiness();

  const std::filesystem::path& readiness_path() const { return readiness_path_; }
  const std::string& token() const { return token_; }
  const std::string& launch_id() const { return launch_id_; }

 private:
  bool RemoveStaleReadiness(std::string* error) const;
  bool WriteProtectedFile(const std::filesystem::path& path,
                          const std::string& contents,
                          std::string* error) const;

  void* lock_handle_ = nullptr;
  std::filesystem::path readiness_path_;
  std::string token_;
  std::string launch_id_;
};

}  // namespace kelpie::windows
