#include <cassert>
#include <string>

#include "base64url.h"
#include "sha256.h"

using kelpie::sync::Base64UrlDecode;
using kelpie::sync::Base64UrlEncode;
using kelpie::sync::Hex;
using kelpie::sync::Sha256;

namespace {

void TestSha256Vectors() {
  // FIPS 180-4 / NIST CAVP examples.
  assert(Hex(Sha256::Hash("")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  assert(Hex(Sha256::Hash("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  assert(Hex(Sha256::Hash("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")) ==
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");

  // One million 'a' bytes, fed in uneven chunks to exercise buffering.
  Sha256 hasher;
  const std::string chunk(997, 'a');
  std::size_t remaining = 1000000;
  while (remaining > 0) {
    const std::size_t take = remaining < chunk.size() ? remaining : chunk.size();
    hasher.Update(chunk.data(), take);
    remaining -= take;
  }
  assert(Hex(hasher.Finish()) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");

  // 55, 56 and 64 byte messages straddle the padding boundary.
  assert(Hex(Sha256::Hash(std::string(55, 'x'))).size() == 64);
  assert(Hex(Sha256::Hash(std::string(56, 'x'))) != Hex(Sha256::Hash(std::string(55, 'x'))));
  assert(Hex(Sha256::Hash(std::string(64, 'x'))) != Hex(Sha256::Hash(std::string(63, 'x'))));
}

void TestBase64Url() {
  assert(Base64UrlEncode("") == "");
  assert(Base64UrlEncode("f") == "Zg");
  assert(Base64UrlEncode("fo") == "Zm8");
  assert(Base64UrlEncode("foo") == "Zm9v");
  assert(Base64UrlEncode("foob") == "Zm9vYg");
  assert(Base64UrlEncode("fooba") == "Zm9vYmE");
  assert(Base64UrlEncode("foobar") == "Zm9vYmFy");
  const std::string binary("\xfb\xff\xfe", 3);
  assert(Base64UrlEncode(binary) == "-__-");

  const auto decoded = Base64UrlDecode("Zm9vYmE");
  assert(decoded.has_value());
  assert(std::string(decoded->begin(), decoded->end()) == "fooba");
  assert(Base64UrlDecode("-__-").has_value());

  assert(!Base64UrlDecode("Zg==").has_value());   // padding is not allowed
  assert(!Base64UrlDecode("Zm9v+g").has_value());  // standard alphabet is not allowed
  assert(!Base64UrlDecode("Z").has_value());       // impossible length
  assert(!Base64UrlDecode("Zh").has_value());      // non-zero trailing bits

  // A SHA-256 digest is exactly UOA's 43-character challenge format.
  const auto digest = Sha256::Hash("challenge");
  assert(Base64UrlEncode(digest.data(), digest.size()).size() == 43);
}

}  // namespace

int main() {
  TestSha256Vectors();
  TestBase64Url();
  return 0;
}
