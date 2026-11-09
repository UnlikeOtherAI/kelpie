#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

namespace kelpie::sync {

// Portable SHA-256 (FIPS 180-4). core-sync carries its own because the Apple
// and Android builds of core/native link no crypto library. It is used only
// for the handshake transcript, the account hint and cookie fingerprints.
class Sha256 {
 public:
  using Digest = std::array<std::uint8_t, 32>;

  Sha256();
  void Update(const void* data, std::size_t size);
  void Update(std::string_view text) { Update(text.data(), text.size()); }
  Digest Finish();

  static Digest Hash(std::string_view text);

 private:
  void Compress(const std::uint8_t* block);

  std::array<std::uint32_t, 8> state_{};
  std::array<std::uint8_t, 64> buffer_{};
  std::size_t buffered_ = 0;
  std::uint64_t total_bytes_ = 0;
  bool finished_ = false;
};

std::string Hex(const Sha256::Digest& digest);

}  // namespace kelpie::sync
