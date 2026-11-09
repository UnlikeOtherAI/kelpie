// OpenSSL 3 (libcrypto) backend for Linux and other POSIX builds.
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/param_build.h>
#include <openssl/rand.h>

#include <stdexcept>

#include "sync_crypto.h"

namespace kelpie::desktop_sync {
namespace {

constexpr const char* kGroup = "prime256v1";

struct PkeyFree { void operator()(EVP_PKEY* key) const { EVP_PKEY_free(key); } };
struct CtxFree { void operator()(EVP_PKEY_CTX* ctx) const { EVP_PKEY_CTX_free(ctx); } };
struct CipherFree { void operator()(EVP_CIPHER_CTX* ctx) const { EVP_CIPHER_CTX_free(ctx); } };
struct BuildFree { void operator()(OSSL_PARAM_BLD* build) const { OSSL_PARAM_BLD_free(build); } };
struct ParamFree { void operator()(OSSL_PARAM* params) const { OSSL_PARAM_free(params); } };
struct BnFree { void operator()(BIGNUM* bn) const { BN_free(bn); } };
using Pkey = std::unique_ptr<EVP_PKEY, PkeyFree>;
using Ctx = std::unique_ptr<EVP_PKEY_CTX, CtxFree>;

// Builds a key from parameters; `selection` is EVP_PKEY_PUBLIC_KEY or EVP_PKEY_KEYPAIR.
Pkey FromData(const Bytes& public_key, const Bytes* scalar, int selection) {
  if (public_key.size() != kPublicKeyBytes || public_key[0] != 0x04) return nullptr;
  std::unique_ptr<OSSL_PARAM_BLD, BuildFree> build(OSSL_PARAM_BLD_new());
  std::unique_ptr<BIGNUM, BnFree> private_value;
  if (!build ||
      !OSSL_PARAM_BLD_push_utf8_string(build.get(), OSSL_PKEY_PARAM_GROUP_NAME, kGroup, 0) ||
      !OSSL_PARAM_BLD_push_octet_string(build.get(), OSSL_PKEY_PARAM_PUB_KEY, public_key.data(),
                                        public_key.size())) return nullptr;
  if (scalar != nullptr) {
    if (scalar->size() != kScalarBytes) return nullptr;
    private_value.reset(BN_bin2bn(scalar->data(), static_cast<int>(scalar->size()), nullptr));
    if (!private_value || !OSSL_PARAM_BLD_push_BN(build.get(), OSSL_PKEY_PARAM_PRIV_KEY, private_value.get())) {
      return nullptr;
    }
  }
  std::unique_ptr<OSSL_PARAM, ParamFree> params(OSSL_PARAM_BLD_to_param(build.get()));
  Ctx ctx(EVP_PKEY_CTX_new_from_name(nullptr, "EC", nullptr));
  EVP_PKEY* raw = nullptr;
  if (!params || !ctx || EVP_PKEY_fromdata_init(ctx.get()) != 1 ||
      EVP_PKEY_fromdata(ctx.get(), &raw, selection, params.get()) != 1) return nullptr;
  Pkey key(raw);
  // Explicit point validation: on the curve, not the identity, correct order.
  Ctx check(EVP_PKEY_CTX_new_from_pkey(nullptr, key.get(), nullptr));
  if (!check || EVP_PKEY_public_check(check.get()) != 1) return nullptr;
  return key;
}

Bytes EncodedPublicKey(EVP_PKEY* key) {
  Bytes out(kPublicKeyBytes);
  std::size_t written = 0;
  if (EVP_PKEY_get_octet_string_param(key, OSSL_PKEY_PARAM_PUB_KEY, out.data(), out.size(), &written) != 1 ||
      written != kPublicKeyBytes || out[0] != 0x04) {
    throw std::runtime_error("P-256 public key export failed");
  }
  return out;
}

}  // namespace

struct EcdhKey::Impl {
  Pkey key;
};

EcdhKey::EcdhKey() : impl_(std::make_unique<Impl>()) {}
EcdhKey::~EcdhKey() = default;

Bytes RandomBytes(std::size_t size) {
  Bytes out(size);
  if (size != 0 && RAND_bytes(out.data(), static_cast<int>(size)) != 1) {
    throw std::runtime_error("CSPRNG failure");
  }
  return out;
}

std::unique_ptr<EcdhKey> EcdhKey::Generate() {
  std::unique_ptr<EcdhKey> result(new EcdhKey());
  result->impl_->key.reset(EVP_PKEY_Q_keygen(nullptr, nullptr, "EC", kGroup));
  if (!result->impl_->key) throw std::runtime_error("P-256 key generation failed");
  // Uncompressed points are the protocol's only encoding (and the default);
  // EncodedPublicKey rejects anything else.
  EVP_PKEY_set_utf8_string_param(result->impl_->key.get(), OSSL_PKEY_PARAM_EC_POINT_CONVERSION_FORMAT,
                                 "uncompressed");
  result->public_key_ = EncodedPublicKey(result->impl_->key.get());
  return result;
}

std::unique_ptr<EcdhKey> EcdhKey::FromPrivate(const Bytes& scalar, const Bytes& public_key) {
  Pkey key = FromData(public_key, &scalar, EVP_PKEY_KEYPAIR);
  if (!key) return nullptr;
  Ctx check(EVP_PKEY_CTX_new_from_pkey(nullptr, key.get(), nullptr));
  if (!check || EVP_PKEY_pairwise_check(check.get()) != 1) return nullptr;
  std::unique_ptr<EcdhKey> result(new EcdhKey());
  result->impl_->key = std::move(key);
  result->public_key_ = public_key;
  return result;
}

std::optional<Bytes> EcdhKey::SharedSecret(const Bytes& peer_public_key) const {
  Pkey peer = FromData(peer_public_key, nullptr, EVP_PKEY_PUBLIC_KEY);
  if (!peer) return std::nullopt;
  Ctx ctx(EVP_PKEY_CTX_new_from_pkey(nullptr, impl_->key.get(), nullptr));
  std::size_t size = 0;
  if (!ctx || EVP_PKEY_derive_init(ctx.get()) != 1 || EVP_PKEY_derive_set_peer(ctx.get(), peer.get()) != 1 ||
      EVP_PKEY_derive(ctx.get(), nullptr, &size) != 1 || size != kScalarBytes) return std::nullopt;
  Bytes secret(size);
  if (EVP_PKEY_derive(ctx.get(), secret.data(), &size) != 1 || size != kScalarBytes) return std::nullopt;
  return secret;
}

bool IsValidPublicKey(const Bytes& public_key) {
  return FromData(public_key, nullptr, EVP_PKEY_PUBLIC_KEY) != nullptr;
}

Bytes HmacSha256(const Bytes& key, const Bytes& data) {
  Bytes out(32);
  unsigned int size = 0;
  static const unsigned char kEmpty = 0;
  if (HMAC(EVP_sha256(), key.empty() ? &kEmpty : key.data(), static_cast<int>(key.size()),
           data.empty() ? &kEmpty : data.data(), data.size(), out.data(), &size) == nullptr || size != 32) {
    throw std::runtime_error("HMAC-SHA256 failed");
  }
  return out;
}

namespace {

std::optional<Bytes> Gcm(bool seal, const Bytes& key, const Bytes& nonce, const Bytes& aad, const Bytes& input) {
  if (key.size() != 32 || nonce.size() != kGcmNonceBytes) return std::nullopt;
  if (!seal && input.size() < kGcmTagBytes) return std::nullopt;
  const std::size_t body = seal ? input.size() : input.size() - kGcmTagBytes;
  std::unique_ptr<EVP_CIPHER_CTX, CipherFree> ctx(EVP_CIPHER_CTX_new());
  if (!ctx || EVP_CipherInit_ex(ctx.get(), EVP_aes_256_gcm(), nullptr, nullptr, nullptr, seal ? 1 : 0) != 1 ||
      EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_SET_IVLEN, static_cast<int>(nonce.size()), nullptr) != 1 ||
      EVP_CipherInit_ex(ctx.get(), nullptr, nullptr, key.data(), nonce.data(), seal ? 1 : 0) != 1) {
    return std::nullopt;
  }
  int written = 0;
  if (!aad.empty() && EVP_CipherUpdate(ctx.get(), nullptr, &written, aad.data(), static_cast<int>(aad.size())) != 1) {
    return std::nullopt;
  }
  Bytes out(body + (seal ? kGcmTagBytes : 0));
  if (body != 0 && EVP_CipherUpdate(ctx.get(), out.data(), &written, input.data(), static_cast<int>(body)) != 1) {
    return std::nullopt;
  }
  if (!seal) {
    Bytes tag(input.end() - kGcmTagBytes, input.end());
    if (EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_SET_TAG, static_cast<int>(kGcmTagBytes), tag.data()) != 1) {
      return std::nullopt;
    }
  }
  unsigned char tail[16];
  if (EVP_CipherFinal_ex(ctx.get(), tail, &written) != 1) return std::nullopt;  // tag mismatch on open
  if (seal && EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_GET_TAG, static_cast<int>(kGcmTagBytes),
                                  out.data() + body) != 1) {
    return std::nullopt;
  }
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
