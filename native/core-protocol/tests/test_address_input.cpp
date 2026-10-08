#include "kelpie/address_input.h"

#include <cassert>
#include <cstring>
#include <iostream>
#include <utility>
#include <vector>

int main() {
  const std::vector<std::pair<std::string, std::string>> cases = {
      {"", ""}, {" \t\n", ""},
      {"GitHub", "https://www.google.com/search?q=GitHub"},
      {"  github  ", "https://www.google.com/search?q=github"},
      {"github issues", "https://www.google.com/search?q=github%20issues"},
      {"cats & dogs#1", "https://www.google.com/search?q=cats%20%26%20dogs%231"},
      {"C++", "https://www.google.com/search?q=C%2B%2B"},
      {"caf\xC3\xA9", "https://www.google.com/search?q=caf%C3%A9"},
      {"\xF0\x9F\x90\x95", "https://www.google.com/search?q=%F0%9F%90%95"},
      {"github.com", "https://github.com"},
      {"GitHub.com/org/repo?q=a#readme", "https://GitHub.com/org/repo?q=a#readme"},
      {"github.com:8443/path", "https://github.com:8443/path"},
      {"localhost:8420", "https://localhost:8420"},
      {"LOCALHOST", "https://LOCALHOST"},
      {"minis.local:8420/health", "https://minis.local:8420/health"},
      {"192.168.1.215:8420", "https://192.168.1.215:8420"},
      {"[::1]:8420/health", "https://[::1]:8420/health"},
      {"[2001:db8::1]", "https://[2001:db8::1]"},
      {"https://github.com", "https://github.com"},
      {"HTTP://localhost:8420", "HTTP://localhost:8420"},
      {"about:blank", "about:blank"}, {"kelpie://start", "kelpie://start"},
      {"file:///tmp/a.html", "file:///tmp/a.html"},
      {"example.com help", "https://www.google.com/search?q=example.com%20help"},
      {"hello..world", "https://www.google.com/search?q=hello..world"},
      {".github", "https://www.google.com/search?q=.github"},
      {"user@example.com", "https://www.google.com/search?q=user%40example.com"},
  };
  for (const auto& [input, expected] : cases) {
    const auto actual = kelpie::ResolveAddressInput(input);
    if (actual != expected) std::cerr << input << ": " << actual << " != " << expected << '\n';
    assert(actual == expected);
    const size_t size = kelpie_resolve_address_input(input.c_str(), nullptr, 0);
    std::vector<char> buffer(size, 'x');
    assert(kelpie_resolve_address_input(input.c_str(), buffer.data(), size) == size);
    assert(expected == buffer.data());
  }
  char small[] = "sentinel";
  kelpie_resolve_address_input("GitHub", small, sizeof(small));
  assert(std::strcmp(small, "sentinel") == 0);
  assert(kelpie_resolve_address_input(nullptr, nullptr, 0) == 1);
  std::cout << "PASS: address input (" << cases.size() << " cases and C bridge)\n";
}
