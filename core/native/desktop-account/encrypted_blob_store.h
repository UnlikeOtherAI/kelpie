#pragma once
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
namespace kelpie::account {
// Platform encrypted storage, atomic and flushed before Save reports success.
// Independent names isolate credentials from the connection result journal.
class EncryptedBlobStore {
 public:
  virtual ~EncryptedBlobStore()=default;
  virtual std::optional<std::string> Load()=0;
  virtual bool Save(const std::string& plain)=0;
  virtual void Clear()=0;
};
std::shared_ptr<EncryptedBlobStore> MakeEncryptedBlobStore(const std::filesystem::path& directory,
    const std::string& name,std::size_t maximum);
}
