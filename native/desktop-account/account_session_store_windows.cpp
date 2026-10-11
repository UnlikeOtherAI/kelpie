// DPAPI session store for Windows: current-user scope, no UI, app-specific
// entropy, written atomically into the per-user profile directory.
#include "encrypted_blob_store.h"
#include <windows.h>
#include <wincrypt.h>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include "account_protocol.h"

namespace kelpie::account {
namespace {



void Wipe(std::string& text) { if (!text.empty()) SecureZeroMemory(text.data(), text.size()); text.clear(); }
DATA_BLOB Blob(const std::string& text) {
  return {static_cast<DWORD>(text.size()), reinterpret_cast<BYTE*>(const_cast<char*>(text.data()))};
}


// Takes ownership of a DPAPI output blob, wiping and freeing it.
std::string Adopt(DATA_BLOB& blob) {
  std::string text(reinterpret_cast<const char*>(blob.pbData), blob.cbData);
  SecureZeroMemory(blob.pbData, blob.cbData);
  LocalFree(blob.pbData);
  return text;
}

std::optional<std::string> ReadSealed(const std::filesystem::path& file, std::size_t maximum) {
  std::error_code error;
  const auto size = std::filesystem::file_size(file, error);
  if (error || size > maximum + 4096) return std::nullopt;
  std::ifstream input(file, std::ios::binary);
  if (!input) return std::nullopt;
  std::string data{std::istreambuf_iterator<char>(input), {}};
  if (input.bad() || data.size() != size) return std::nullopt;
  return data;
}

// Temp file + flush + replace, so a crash leaves either the old or the new file.
bool WriteSealed(const std::filesystem::path& file, const std::string& data) {
  std::error_code error;
  std::filesystem::create_directories(file.parent_path(), error);
  if (error) return false;
  const std::filesystem::path temp = file.wstring() + L"." +
      std::filesystem::path(RandomAccountValue()).wstring() + L".tmp";
  HANDLE handle = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool flushed = WriteFile(handle, data.data(), static_cast<DWORD>(data.size()), &written, nullptr) &&
      written == data.size() && FlushFileBuffers(handle);
  CloseHandle(handle);
  if (!flushed || !MoveFileExW(temp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temp.c_str());
    return false;
  }
  return true;
}

class DpapiBlobStore final : public EncryptedBlobStore {
 public:
  DpapiBlobStore(std::filesystem::path file, std::string entropy, std::size_t maximum)
      : file_(std::move(file)), entropy_(std::move(entropy)), maximum_(maximum) {}

  std::optional<std::string> Load() override {
    std::error_code error;
    if (!std::filesystem::exists(file_, error)) return std::nullopt;
    const auto sealed = ReadSealed(file_, maximum_);
    std::optional<std::string> session;
    if (sealed) {
      DATA_BLOB input = Blob(*sealed), entropy = Blob(entropy_), output{};
      if (CryptUnprotectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        auto plain = Adopt(output);
        if (plain.size() <= maximum_) session = std::move(plain);
        Wipe(plain);
      }
    }
    if (!session) throw std::runtime_error("Encrypted data unavailable");
    return session;
  }

  bool Save(const std::string& value) override {
    if (value.size() > maximum_) return false;
    auto plain = value;
    DATA_BLOB input = Blob(plain), entropy = Blob(entropy_), output{};
    const BOOL sealed = CryptProtectData(&input, L"Kelpie UOA session", &entropy, nullptr, nullptr,
                                         CRYPTPROTECT_UI_FORBIDDEN, &output);
    Wipe(plain);
    return sealed && WriteSealed(file_, Adopt(output));
  }

  void Clear() override { if(!DeleteFileW(file_.c_str()) && GetLastError()!=ERROR_FILE_NOT_FOUND && GetLastError()!=ERROR_PATH_NOT_FOUND)throw std::runtime_error("Encrypted data unavailable"); }

 private:
  std::filesystem::path file_;
  std::string entropy_;
  std::size_t maximum_;
};
}  // namespace

std::shared_ptr<EncryptedBlobStore> MakeEncryptedBlobStore(const std::filesystem::path& directory,
    const std::string& name, std::size_t maximum) {
  return std::make_shared<DpapiBlobStore>(directory / name,
      "com.unlikeotherai.kelpie/" + name, maximum);
}
}  // namespace kelpie::account
