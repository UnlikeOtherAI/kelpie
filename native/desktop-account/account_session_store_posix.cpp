// AES-256-GCM session store for Linux. The random key lives in its own 0600
// file beside the sealed session, inside a 0700 directory the store owns, so it
// works headless without Secret Service or a desktop keyring.
#include "account_session_store.h"
#include <fcntl.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include "account_protocol.h"

namespace kelpie::account {
namespace {
constexpr char kMagic[] = "KUS1";
constexpr std::size_t kMagicSize = 4, kKeySize = 32, kNonceSize = 12, kTagSize = 16, kMaxSealed = 16384;
using Context = std::unique_ptr<EVP_CIPHER_CTX, decltype(&EVP_CIPHER_CTX_free)>;

unsigned char* Bytes(std::string& text) { return reinterpret_cast<unsigned char*>(text.data()); }
const unsigned char* Bytes(const std::string& text) { return reinterpret_cast<const unsigned char*>(text.data()); }
void Wipe(std::string& text) { if (!text.empty()) OPENSSL_cleanse(text.data(), text.size()); text.clear(); }
const std::string& Aad() { static const std::string aad(kAccountSessionKey); return aad; }

bool Exists(const std::filesystem::path& path) { struct stat info {}; return lstat(path.c_str(), &info) == 0; }

// The directory must be a real 0700 directory owned by this user.
bool SecureDirectory(const std::filesystem::path& directory, bool create) {
  if (create) {
    std::error_code error;
    std::filesystem::create_directories(directory.parent_path(), error);
    if (mkdir(directory.c_str(), 0700) != 0 && errno != EEXIST) return false;
  }
  struct stat info {};
  if (lstat(directory.c_str(), &info) != 0 || !S_ISDIR(info.st_mode) || info.st_uid != getuid()) return false;
  return (info.st_mode & 0777) == 0700 || chmod(directory.c_str(), 0700) == 0;
}

std::optional<std::string> ReadPrivate(const std::filesystem::path& file, std::size_t limit) {
  const int fd = open(file.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return std::nullopt;
  std::optional<std::string> result;
  struct stat info {};
  if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == getuid() &&
      static_cast<std::size_t>(info.st_size) <= limit && ((info.st_mode & 077) == 0 || fchmod(fd, 0600) == 0)) {
    std::string data(static_cast<std::size_t>(info.st_size), '\0');
    std::size_t offset = 0;
    while (offset < data.size()) {
      const auto count = read(fd, data.data() + offset, data.size() - offset);
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0) break;
      offset += static_cast<std::size_t>(count);
    }
    if (offset == data.size()) result = std::move(data); else Wipe(data);
  }
  close(fd);
  return result;
}

// Temp file + fsync + rename, so a crash leaves either the old or the new file.
bool WritePrivate(const std::filesystem::path& file, const std::string& data) {
  const auto temp = file.string() + "." + RandomAccountValue() + ".tmp";
  const int fd = open(temp.c_str(), O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0) return false;
  std::size_t offset = 0;
  while (offset < data.size()) {
    const auto count = write(fd, data.data() + offset, data.size() - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    offset += static_cast<std::size_t>(count);
  }
  const bool written = offset == data.size() && fsync(fd) == 0;
  close(fd);
  if (!written || rename(temp.c_str(), file.c_str()) != 0) { unlink(temp.c_str()); return false; }
  const int directory = open(file.parent_path().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (directory >= 0) { fsync(directory); close(directory); }
  return true;
}

std::optional<std::string> Seal(const std::string& key, const std::string& plain) {
  std::string nonce(kNonceSize, '\0'), cipher(plain.size(), '\0'), tag(kTagSize, '\0');
  if (RAND_bytes(Bytes(nonce), static_cast<int>(kNonceSize)) != 1) return std::nullopt;
  Context context(EVP_CIPHER_CTX_new(), EVP_CIPHER_CTX_free);
  int length = 0, tail = 0;
  const bool sealed = context &&
      EVP_EncryptInit_ex(context.get(), EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1 &&
      EVP_CIPHER_CTX_ctrl(context.get(), EVP_CTRL_GCM_SET_IVLEN, static_cast<int>(kNonceSize), nullptr) == 1 &&
      EVP_EncryptInit_ex(context.get(), nullptr, nullptr, Bytes(key), Bytes(nonce)) == 1 &&
      EVP_EncryptUpdate(context.get(), nullptr, &length, Bytes(Aad()), static_cast<int>(Aad().size())) == 1 &&
      EVP_EncryptUpdate(context.get(), Bytes(cipher), &length, Bytes(plain), static_cast<int>(plain.size())) == 1 &&
      EVP_EncryptFinal_ex(context.get(), Bytes(cipher) + length, &tail) == 1 &&
      EVP_CIPHER_CTX_ctrl(context.get(), EVP_CTRL_GCM_GET_TAG, static_cast<int>(kTagSize), tag.data()) == 1;
  if (!sealed) return std::nullopt;
  return std::string(kMagic, kMagicSize) + nonce + cipher + tag;
}

std::optional<std::string> Unseal(const std::string& key, const std::string& sealed) {
  if (sealed.size() <= kMagicSize + kNonceSize + kTagSize || sealed.compare(0, kMagicSize, kMagic) != 0)
    return std::nullopt;
  const auto nonce = sealed.substr(kMagicSize, kNonceSize);
  const auto cipher = sealed.substr(kMagicSize + kNonceSize, sealed.size() - kMagicSize - kNonceSize - kTagSize);
  auto tag = sealed.substr(sealed.size() - kTagSize);
  std::string plain(cipher.size(), '\0');
  Context context(EVP_CIPHER_CTX_new(), EVP_CIPHER_CTX_free);
  int length = 0, tail = 0;
  const bool opened = context &&
      EVP_DecryptInit_ex(context.get(), EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1 &&
      EVP_CIPHER_CTX_ctrl(context.get(), EVP_CTRL_GCM_SET_IVLEN, static_cast<int>(kNonceSize), nullptr) == 1 &&
      EVP_DecryptInit_ex(context.get(), nullptr, nullptr, Bytes(key), Bytes(nonce)) == 1 &&
      EVP_DecryptUpdate(context.get(), nullptr, &length, Bytes(Aad()), static_cast<int>(Aad().size())) == 1 &&
      EVP_DecryptUpdate(context.get(), Bytes(plain), &length, Bytes(cipher), static_cast<int>(cipher.size())) == 1 &&
      EVP_CIPHER_CTX_ctrl(context.get(), EVP_CTRL_GCM_SET_TAG, static_cast<int>(kTagSize), tag.data()) == 1 &&
      EVP_DecryptFinal_ex(context.get(), Bytes(plain) + length, &tail) == 1;
  if (!opened) { Wipe(plain); return std::nullopt; }
  plain.resize(static_cast<std::size_t>(length + tail));
  return plain;
}

class EncryptedFileSessionStore final : public AccountSessionStore {
 public:
  explicit EncryptedFileSessionStore(std::filesystem::path directory)
      : directory_(std::move(directory)), session_(directory_ / kAccountSessionKey),
        key_(directory_ / (std::string(kAccountSessionKey) + ".key")) {}

  std::optional<AccountSession> Load() override {
    if (!SecureDirectory(directory_, false) || !Exists(session_)) return std::nullopt;
    auto key = ReadPrivate(key_, kKeySize);
    const auto sealed = ReadPrivate(session_, kMaxSealed);
    std::optional<AccountSession> session;
    if (key && key->size() == kKeySize && sealed) {
      if (auto plain = Unseal(*key, *sealed)) { session = DecodeAccountSession(*plain); Wipe(*plain); }
    }
    if (key) Wipe(*key);
    if (!session) Clear();
    return session;
  }

  bool Save(const AccountSession& session) override {
    if (!SecureDirectory(directory_, true)) return false;
    auto key = ReadPrivate(key_, kKeySize);
    if (!key || key->size() != kKeySize) {
      key = std::string(kKeySize, '\0');
      if (RAND_bytes(Bytes(*key), static_cast<int>(kKeySize)) != 1 || !WritePrivate(key_, *key)) {
        Wipe(*key);
        return false;
      }
    }
    auto plain = EncodeAccountSession(session);
    const auto sealed = Seal(*key, plain);
    Wipe(plain);
    Wipe(*key);
    return sealed && WritePrivate(session_, *sealed);
  }

  void Clear() override {
    unlink(session_.c_str());
    unlink(key_.c_str());
  }

 private:
  std::filesystem::path directory_, session_, key_;
};
}  // namespace

std::shared_ptr<AccountSessionStore> MakeAccountSessionStore(const std::filesystem::path& directory) {
  return std::make_shared<EncryptedFileSessionStore>(directory / "uoa");
}
}  // namespace kelpie::account
