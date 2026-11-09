// Backend-independent HKDF (RFC 5869) over the platform HMAC-SHA256.
#include <stdexcept>

#include "sync_crypto.h"

namespace kelpie::desktop_sync {

Bytes HkdfSha256(const Bytes& ikm, const Bytes& salt, std::string_view info, std::size_t length) {
  constexpr std::size_t kHashBytes = 32;
  if (length == 0 || length > 255 * kHashBytes) throw std::invalid_argument("HKDF length");
  const Bytes prk = HmacSha256(salt.empty() ? Bytes(kHashBytes, 0) : salt, ikm);
  Bytes output;
  Bytes block;
  for (std::uint8_t counter = 1; output.size() < length; ++counter) {
    Bytes input = block;
    input.insert(input.end(), info.begin(), info.end());
    input.push_back(counter);
    block = HmacSha256(prk, input);
    output.insert(output.end(), block.begin(), block.end());
  }
  output.resize(length);
  return output;
}

}  // namespace kelpie::desktop_sync
