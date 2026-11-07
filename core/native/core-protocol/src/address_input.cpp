#include "kelpie/address_input.h"

#include <algorithm>
#include <cstring>

namespace {
bool IsLetter(unsigned char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

bool IsDigit(unsigned char c) { return c >= '0' && c <= '9'; }

bool HasScheme(std::string_view value) {
  const auto colon = value.find(':');
  if (colon == std::string_view::npos || colon == 0 || !IsLetter(value.front())) return false;
  // A host:port is an address, not a scheme (localhost:8420, example.com:8080).
  const auto port_end = value.find_first_of("/?#", colon + 1);
  const auto port = value.substr(colon + 1, port_end - colon - 1);
  if (!port.empty() && std::all_of(port.begin(), port.end(), IsDigit)) return false;
  return std::all_of(value.begin(), value.begin() + colon, [](unsigned char c) {
    return IsLetter(c) || IsDigit(c) || c == '+' || c == '-' || c == '.';
  });
}

bool IsHost(std::string_view value) {
  auto host = value.substr(0, value.find_first_of("/?#"));
  if (host.empty() || host.find('@') != std::string_view::npos) return false;
  // Bracketed IPv6, optionally followed by a port.
  if (host.front() == '[') {
    const auto close = host.find(']');
    if (close == std::string_view::npos || host.substr(1, close - 1).find(':') == std::string_view::npos) return false;
    const auto tail = host.substr(close + 1);
    return tail.empty() || (tail.front() == ':' && tail.size() > 1 &&
        std::all_of(tail.begin() + 1, tail.end(), IsDigit));
  }
  const auto colon = host.find(':');
  if (colon != std::string_view::npos) {
    const auto port = host.substr(colon + 1);
    if (port.empty() || !std::all_of(port.begin(), port.end(), IsDigit)) return false;
    host = host.substr(0, colon);
  }
  std::string lowered(host);
  std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char c) {
    return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c;
  });
  if (lowered == "localhost") return true;
  if (host.find('.') == std::string_view::npos) return false;
  if (host.back() == '.') host.remove_suffix(1);
  while (!host.empty()) {
    const auto dot = host.find('.');
    const auto label = host.substr(0, dot);
    if (label.empty() || label.front() == '-' || label.back() == '-') return false;
    if (!std::all_of(label.begin(), label.end(), [](unsigned char c) {
      return IsLetter(c) || IsDigit(c) || c == '-' || c >= 0x80;
    })) return false;
    if (dot == std::string_view::npos) return true;
    host.remove_prefix(dot + 1);
  }
  return false;
}

std::string Search(std::string_view value) {
  constexpr char hex[] = "0123456789ABCDEF";
  std::string result = "https://www.google.com/search?q=";
  for (const unsigned char c : value) {
    if (IsLetter(c) || IsDigit(c) || c == '-' || c == '_' || c == '.' || c == '~') {
      result += static_cast<char>(c);
    } else {
      result += '%';
      result += hex[c >> 4];
      result += hex[c & 15];
    }
  }
  return result;
}
}  // namespace

std::string kelpie::ResolveAddressInput(std::string_view input) {
  const auto first = input.find_first_not_of(" \t\r\n");
  if (first == std::string_view::npos) return {};
  input = input.substr(first, input.find_last_not_of(" \t\r\n") - first + 1);
  if (HasScheme(input)) return std::string(input);
  if (input.find_first_of(" \t\r\n") == std::string_view::npos && IsHost(input)) {
    return "https://" + std::string(input);
  }
  return Search(input);
}

size_t kelpie_resolve_address_input(const char* input, char* output, size_t capacity) {
  const auto resolved = kelpie::ResolveAddressInput(input == nullptr ? "" : input);
  const auto required = resolved.size() + 1;
  if (output != nullptr && capacity >= required) std::memcpy(output, resolved.c_str(), required);
  return required;
}
