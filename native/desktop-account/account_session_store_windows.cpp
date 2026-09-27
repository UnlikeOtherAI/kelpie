// DPAPI session store for Windows: current-user scope, no UI, app-specific
// entropy, written atomically into the per-user profile directory.
#include "account_session_store.h"
#include <windows.h>
#include <wincrypt.h>
#include <cstdint>
#include <fstream>
#include <iterator>
#include "account_protocol.h"

namespace kelpie::account {
namespace {
constexpr char kEntropy[] = "com.unlikeotherai.kelpie/uoa.session.v1";
constexpr std::uintmax_t kMaxSealed = 65536;

void Wipe(std::string& text) { if (!text.empty()) SecureZeroMemory(text.data(), text.size()); text.clear(); }
DATA_BLOB Blob(const std::string& text) {
  return {static_cast<DWORD>(text.size()), reinterpret_cast<BYTE*>(const_cast<char*>(text.data()))};
}
DATA_BLOB Entropy() { return {sizeof(kEntropy) - 1, reinterpret_cast<BYTE*>(const_cast<char*>(kEntropy))}; }

// Takes ownership of a DPAPI output blob, wiping and freeing it.
std::string Adopt(DATA_BLOB& blob) {
  std::string text(reinterpret_cast<const char*>(blob.pbData), blob.cbData);
  SecureZeroMemory(blob.pbData, blob.cbData);
  LocalFree(blob.pbData);
  return text;
}

std::optional<std::string> ReadSealed(const std::filesystem::path& file) {
  std::error_code error;
  const auto size = std::filesystem::file_size(file, error);
  if (error || size > kMaxSealed) return std::nullopt;
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

class DpapiSessionStore final : public AccountSessionStore {
 public:
  explicit DpapiSessionStore(std::filesystem::path file) : file_(std::move(file)) {}

  std::optional<AccountSession> Load() override {
    std::error_code error;
    if (!std::filesystem::exists(file_, error)) return std::nullopt;
    const auto sealed = ReadSealed(file_);
    std::optional<AccountSession> session;
    if (sealed) {
      DATA_BLOB input = Blob(*sealed), entropy = Entropy(), output{};
      if (CryptUnprotectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
        auto plain = Adopt(output);
        session = DecodeAccountSession(plain);
        Wipe(plain);
      }
    }
    if (!session) Clear();
    return session;
  }

  bool Save(const AccountSession& session) override {
    auto plain = EncodeAccountSession(session);
    DATA_BLOB input = Blob(plain), entropy = Entropy(), output{};
    const BOOL sealed = CryptProtectData(&input, L"Kelpie UOA session", &entropy, nullptr, nullptr,
                                         CRYPTPROTECT_UI_FORBIDDEN, &output);
    Wipe(plain);
    return sealed && WriteSealed(file_, Adopt(output));
  }

  void Clear() override { DeleteFileW(file_.c_str()); }

 private:
  std::filesystem::path file_;
};
}  // namespace

std::shared_ptr<AccountSessionStore> MakeAccountSessionStore(const std::filesystem::path& directory) {
  return std::make_shared<DpapiSessionStore>(directory / kAccountSessionKey);
}
}  // namespace kelpie::account
