// Windows CNG (bcrypt) backend.
#include <windows.h>
#include <bcrypt.h>

#include <algorithm>
#include <cstring>
#include <stdexcept>

#include "sync_crypto.h"

namespace kelpie::desktop_sync {
namespace {

bool Ok(NTSTATUS status) { return status >= 0; }

class Algorithm {
 public:
  Algorithm(LPCWSTR id, ULONG flags = 0) {
    if (!Ok(BCryptOpenAlgorithmProvider(&handle_, id, nullptr, flags))) handle_ = nullptr;
  }
  ~Algorithm() { if (handle_) BCryptCloseAlgorithmProvider(handle_, 0); }
  Algorithm(const Algorithm&) = delete;
  Algorithm& operator=(const Algorithm&) = delete;
  BCRYPT_ALG_HANDLE get() const { return handle_; }
  explicit operator bool() const { return handle_ != nullptr; }

 private:
  BCRYPT_ALG_HANDLE handle_ = nullptr;
};

struct KeyHandle {
  BCRYPT_KEY_HANDLE handle = nullptr;
  KeyHandle() = default;
  KeyHandle(const KeyHandle&) = delete;
  KeyHandle& operator=(const KeyHandle&) = delete;
  ~KeyHandle() { if (handle) BCryptDestroyKey(handle); }
};

struct SecretHandle {
  BCRYPT_SECRET_HANDLE handle = nullptr;
  ~SecretHandle() { if (handle) BCryptDestroySecret(handle); }
};

const Algorithm& Ecdh() {
  static const Algorithm algorithm(BCRYPT_ECDH_P256_ALGORITHM);
  return algorithm;
}

// BCRYPT_ECCKEY_BLOB header followed by X, Y and (private blobs) d.
Bytes KeyBlob(ULONG magic, const Bytes& public_key, const Bytes* scalar) {
  BCRYPT_ECCKEY_BLOB header{magic, static_cast<ULONG>(kScalarBytes)};
  Bytes blob(sizeof(header));
  std::memcpy(blob.data(), &header, sizeof(header));
  blob.insert(blob.end(), public_key.begin() + 1, public_key.end());
  if (scalar) blob.insert(blob.end(), scalar->begin(), scalar->end());
  return blob;
}

// CNG validates the point when it imports a public key unless told not to
// (BCRYPT_NO_KEY_VALIDATION), so an invalid point never becomes a key.
bool ImportPublic(const Bytes& public_key, KeyHandle* key) {
  if (!Ecdh() || public_key.size() != kPublicKeyBytes || public_key[0] != 0x04) return false;
  Bytes blob = KeyBlob(BCRYPT_ECDH_PUBLIC_P256_MAGIC, public_key, nullptr);
  return Ok(BCryptImportKeyPair(Ecdh().get(), nullptr, BCRYPT_ECCPUBLIC_BLOB, &key->handle, blob.data(),
                                static_cast<ULONG>(blob.size()), 0));
}

}  // namespace

struct EcdhKey::Impl {
  KeyHandle key;
};

EcdhKey::EcdhKey() : impl_(std::make_unique<Impl>()) {}
EcdhKey::~EcdhKey() = default;

Bytes RandomBytes(std::size_t size) {
  Bytes out(size);
  if (size != 0 && !Ok(BCryptGenRandom(nullptr, out.data(), static_cast<ULONG>(size),
                                       BCRYPT_USE_SYSTEM_PREFERRED_RNG))) {
    throw std::runtime_error("CSPRNG failure");
  }
  return out;
}

std::unique_ptr<EcdhKey> EcdhKey::Generate() {
  if (!Ecdh()) throw std::runtime_error("P-256 ECDH is unavailable");
  std::unique_ptr<EcdhKey> result(new EcdhKey());
  auto& key = result->impl_->key.handle;
  if (!Ok(BCryptGenerateKeyPair(Ecdh().get(), &key, 256, 0)) || !Ok(BCryptFinalizeKeyPair(key, 0))) {
    throw std::runtime_error("P-256 key generation failed");
  }
  ULONG size = 0;
  if (!Ok(BCryptExportKey(key, nullptr, BCRYPT_ECCPUBLIC_BLOB, nullptr, 0, &size, 0))) {
    throw std::runtime_error("P-256 public key export failed");
  }
  Bytes blob(size);
  if (!Ok(BCryptExportKey(key, nullptr, BCRYPT_ECCPUBLIC_BLOB, blob.data(), size, &size, 0)) ||
      size != sizeof(BCRYPT_ECCKEY_BLOB) + 2 * kScalarBytes) {
    throw std::runtime_error("P-256 public key export failed");
  }
  result->public_key_.assign(1, 0x04);
  result->public_key_.insert(result->public_key_.end(), blob.begin() + sizeof(BCRYPT_ECCKEY_BLOB), blob.end());
  return result;
}

std::unique_ptr<EcdhKey> EcdhKey::FromPrivate(const Bytes& scalar, const Bytes& public_key) {
  if (!Ecdh() || scalar.size() != kScalarBytes || public_key.size() != kPublicKeyBytes || public_key[0] != 0x04) {
    return nullptr;
  }
  std::unique_ptr<EcdhKey> result(new EcdhKey());
  Bytes blob = KeyBlob(BCRYPT_ECDH_PRIVATE_P256_MAGIC, public_key, &scalar);
  const bool imported = Ok(BCryptImportKeyPair(Ecdh().get(), nullptr, BCRYPT_ECCPRIVATE_BLOB,
                                               &result->impl_->key.handle, blob.data(),
                                               static_cast<ULONG>(blob.size()), 0));
  SecureZeroMemory(blob.data(), blob.size());
  if (!imported) return nullptr;
  result->public_key_ = public_key;
  return result;
}

std::optional<Bytes> EcdhKey::SharedSecret(const Bytes& peer_public_key) const {
  KeyHandle peer;
  if (!ImportPublic(peer_public_key, &peer)) return std::nullopt;
  SecretHandle secret;
  if (!Ok(BCryptSecretAgreement(impl_->key.handle, peer.handle, &secret.handle, 0))) return std::nullopt;
  Bytes out(kScalarBytes);
  ULONG size = 0;
  if (!Ok(BCryptDeriveKey(secret.handle, BCRYPT_KDF_RAW_SECRET, nullptr, out.data(),
                          static_cast<ULONG>(out.size()), &size, 0)) || size != kScalarBytes) {
    return std::nullopt;
  }
  // BCRYPT_KDF_RAW_SECRET returns the X coordinate little-endian.
  std::reverse(out.begin(), out.end());
  return out;
}

bool IsValidPublicKey(const Bytes& public_key) {
  KeyHandle key;
  return ImportPublic(public_key, &key);
}

Bytes HmacSha256(const Bytes& key, const Bytes& data) {
  static const Algorithm hmac(BCRYPT_SHA256_ALGORITHM, BCRYPT_ALG_HANDLE_HMAC_FLAG);
  if (!hmac) throw std::runtime_error("HMAC-SHA256 is unavailable");
  BCRYPT_HASH_HANDLE hash = nullptr;
  UCHAR empty = 0;
  Bytes out(32);
  const bool ok = Ok(BCryptCreateHash(hmac.get(), &hash, nullptr, 0,
                                      key.empty() ? &empty : const_cast<PUCHAR>(key.data()),
                                      static_cast<ULONG>(key.size()), 0)) &&
                  (data.empty() || Ok(BCryptHashData(hash, const_cast<PUCHAR>(data.data()),
                                                     static_cast<ULONG>(data.size()), 0))) &&
                  Ok(BCryptFinishHash(hash, out.data(), static_cast<ULONG>(out.size()), 0));
  if (hash) BCryptDestroyHash(hash);
  if (!ok) throw std::runtime_error("HMAC-SHA256 failed");
  return out;
}

namespace {

std::optional<Bytes> Gcm(bool seal, const Bytes& key, const Bytes& nonce, const Bytes& aad, const Bytes& input) {
  static const Algorithm aes(BCRYPT_AES_ALGORITHM);
  static const bool gcm = aes && Ok(BCryptSetProperty(aes.get(), BCRYPT_CHAINING_MODE,
      reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(BCRYPT_CHAIN_MODE_GCM)),
      static_cast<ULONG>(sizeof(BCRYPT_CHAIN_MODE_GCM)), 0));
  if (!gcm || key.size() != 32 || nonce.size() != kGcmNonceBytes) return std::nullopt;
  if (!seal && input.size() < kGcmTagBytes) return std::nullopt;
  const std::size_t body = seal ? input.size() : input.size() - kGcmTagBytes;
  KeyHandle handle;
  if (!Ok(BCryptGenerateSymmetricKey(aes.get(), &handle.handle, nullptr, 0, const_cast<PUCHAR>(key.data()),
                                     static_cast<ULONG>(key.size()), 0))) {
    return std::nullopt;
  }
  Bytes tag(kGcmTagBytes);
  if (!seal) std::copy(input.end() - kGcmTagBytes, input.end(), tag.begin());
  Bytes nonce_copy = nonce;
  Bytes aad_copy = aad;
  BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
  BCRYPT_INIT_AUTH_MODE_INFO(info);
  info.pbNonce = nonce_copy.data();
  info.cbNonce = static_cast<ULONG>(nonce_copy.size());
  info.pbAuthData = aad_copy.empty() ? nullptr : aad_copy.data();
  info.cbAuthData = static_cast<ULONG>(aad_copy.size());
  info.pbTag = tag.data();
  info.cbTag = static_cast<ULONG>(tag.size());
  Bytes in(input.begin(), input.begin() + static_cast<std::ptrdiff_t>(body));
  Bytes out(body);
  UCHAR scratch = 0;
  ULONG written = 0;
  const NTSTATUS status = seal
      ? BCryptEncrypt(handle.handle, body ? in.data() : &scratch, static_cast<ULONG>(body), &info, nullptr, 0,
                      body ? out.data() : &scratch, static_cast<ULONG>(body), &written, 0)
      : BCryptDecrypt(handle.handle, body ? in.data() : &scratch, static_cast<ULONG>(body), &info, nullptr, 0,
                      body ? out.data() : &scratch, static_cast<ULONG>(body), &written, 0);
  if (!Ok(status) || written != body) return std::nullopt;  // STATUS_AUTH_TAG_MISMATCH on a forged box
  if (seal) out.insert(out.end(), tag.begin(), tag.end());
  return out;
}

}  // namespace

std::optional<Bytes> AesGcmSeal(const Bytes& key, const Bytes& nonce, const Bytes& aad, const Bytes& plaintext) {
  return Gcm(true, key, nonce, aad, plaintext);
}

std::optional<Bytes> AesGcmOpen(const Bytes& key, const Bytes& nonce, const Bytes& aad, const Bytes& box) {
  return Gcm(false, key, nonce, aad, box);
}

}  // namespace kelpie::desktop_sync
