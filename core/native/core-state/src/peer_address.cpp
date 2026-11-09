#include "kelpie/peer_trust.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <fstream>
#include <stdexcept>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <bcrypt.h>
#else
#include <arpa/inet.h>
#include <unistd.h>
#endif

namespace kelpie {

std::optional<std::string> CanonicalPeerAddress(const std::string& input) {
  if (input.empty() || input.size() > 128 || input.find('\0') != std::string::npos) return std::nullopt;
  std::string address = input;
  if (address.front() == '[' && address.back() == ']') address = address.substr(1, address.size() - 2);
  std::string scope;
  const auto percent = address.find('%');
  if (percent != std::string::npos) {
    scope = address.substr(percent);
    address.resize(percent);
    if (scope.size() < 2 || !std::all_of(scope.begin() + 1, scope.end(), [](unsigned char c) {
          return std::isalnum(c) || c == '_' || c == '-' || c == '.';
        })) return std::nullopt;
  }
  std::array<unsigned char, 16> bytes{};
  char formatted[INET6_ADDRSTRLEN]{};
  if (scope.empty() && inet_pton(AF_INET, address.c_str(), bytes.data()) == 1) {
    if (!inet_ntop(AF_INET, bytes.data(), formatted, sizeof(formatted))) return std::nullopt;
    return std::string(formatted);
  }
  if (inet_pton(AF_INET6, address.c_str(), bytes.data()) != 1) return std::nullopt;
  const bool mapped = std::all_of(bytes.begin(), bytes.begin() + 10, [](unsigned char b) { return b == 0; }) &&
                      bytes[10] == 255 && bytes[11] == 255;
  if (mapped) {
    if (!scope.empty() || !inet_ntop(AF_INET, bytes.data() + 12, formatted, sizeof(formatted))) return std::nullopt;
  } else if (!inet_ntop(AF_INET6, bytes.data(), formatted, sizeof(formatted))) return std::nullopt;
  return std::string(formatted) + scope;
}

bool IsLoopbackPeer(const std::string& input) {
  const auto address = CanonicalPeerAddress(input);
  return address && (*address == "::1" || address->rfind("127.", 0) == 0);
}

bool IsSafeControlHost(const std::string& host) {
  if (host.empty()) return false;
  std::string name = host;
  if (name.front() == '[') {
    const auto end = name.find(']');
    if (end == std::string::npos) return false;
    if (end + 1 < name.size() && (end + 2 >= name.size() || name[end + 1] != ':' ||
        !std::all_of(name.begin() + end + 2, name.end(), [](unsigned char c) { return std::isdigit(c); }))) return false;
    name = name.substr(0, end + 1);
  } else {
    const auto colon = name.find(':');
    if (colon != std::string::npos) {
      if (colon + 1 == name.size() || !std::all_of(name.begin() + colon + 1, name.end(), [](unsigned char c) {
            return std::isdigit(c);
          })) return false;
      name.resize(colon);
    }
  }
  if (CanonicalPeerAddress(name)) return true;
  std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return std::tolower(c); });
  if (name == "localhost") return true;
  char machine[256]{};
  if (gethostname(machine, sizeof(machine) - 1) != 0) return false;
  std::string own = machine;
  std::transform(own.begin(), own.end(), own.begin(), [](unsigned char c) { return std::tolower(c); });
  return name == own || (own.find('.') == std::string::npos && name == own + ".local");
}

std::string PeerRequestNonce() {
  std::array<unsigned char, 32> bytes{};
#ifdef _WIN32
  if (BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()), BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
    throw std::runtime_error("Secure randomness unavailable");
#else
  std::ifstream random("/dev/urandom", std::ios::binary);
  if (!random.read(reinterpret_cast<char*>(bytes.data()), bytes.size()))
    throw std::runtime_error("Secure randomness unavailable");
#endif
  constexpr char hex[] = "0123456789abcdef";
  std::string result;
  for (const auto byte : bytes) { result += hex[byte >> 4]; result += hex[byte & 15]; }
  return result;
}

}  // namespace kelpie
