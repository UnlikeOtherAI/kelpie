#include <cassert>
#include <iostream>
#include <string>
#include <vector>

#include "kelpie/favicon_registry.h"

using kelpie::FaviconRegistry;

namespace {

void TestHostKeying() {
  // Keys are hosts, not URLs, and hosts are case-insensitive.
  assert(FaviconRegistry::HostForUrl("https://Example.COM/path?q=1#frag") == "example.com");
  assert(FaviconRegistry::HostForUrl("https://example.com:8443/") == "example.com");
  assert(FaviconRegistry::HostForUrl("https://user:secret@example.com/") == "example.com");
  assert(FaviconRegistry::HostForUrl("http://[2001:db8::1]:8080/a") == "[2001:db8::1]");
  assert(FaviconRegistry::HostForUrl("https://example.com") == "example.com");

  // No authority means no host, so the caller falls back to a letter avatar.
  assert(FaviconRegistry::HostForUrl("about:blank").empty());
  assert(FaviconRegistry::HostForUrl("data:image/png;base64,AAAA").empty());
  assert(FaviconRegistry::HostForUrl("").empty());

  // Kelpie's own scheme still yields its host, so the start page could be keyed
  // like any other origin if a caller ever asks.
  assert(FaviconRegistry::HostForUrl("kelpie://start/data.json") == "start");

  FaviconRegistry registry(4);
  assert(registry.Store("Example.COM", "AAAA"));
  assert(registry.Peek("example.com").value() == "AAAA");
  assert(registry.Peek("EXAMPLE.com").value() == "AAAA");
  assert(!registry.Peek("other.test").has_value());

  // A later download for the same host replaces the earlier payload.
  assert(registry.Store("example.com", "BBBB"));
  assert(registry.Peek("example.com").value() == "BBBB");
  assert(registry.size() == 1);
}

void TestIgnoresEmptyInput() {
  FaviconRegistry registry(4);
  // A failed download must not create or evict an entry.
  assert(!registry.Store("", "AAAA"));
  assert(!registry.Store("example.com", ""));
  assert(registry.size() == 0);
}

void TestEvictsLeastRecentlyUsed() {
  FaviconRegistry registry(3);
  registry.Store("a.test", "A");
  registry.Store("b.test", "B");
  registry.Store("c.test", "C");
  assert(registry.size() == 3);

  // Reading `a.test` promotes it, so `b.test` becomes the eviction victim.
  assert(registry.Lookup("a.test").value() == "A");
  registry.Store("d.test", "D");

  assert(registry.size() == 3);
  assert(!registry.Peek("b.test").has_value());
  const std::vector<std::string> expected{"d.test", "a.test", "c.test"};
  assert(registry.HostsMostRecentFirst() == expected);

  // Peek must not reorder, otherwise a snapshot read would change eviction.
  registry.Peek("c.test");
  assert(registry.HostsMostRecentFirst() == expected);

  registry.Clear();
  assert(registry.size() == 0);
  assert(!registry.Peek("a.test").has_value());
}

void TestRewriteKeepsCapacity() {
  FaviconRegistry registry(2);
  registry.Store("a.test", "A");
  registry.Store("b.test", "B");
  registry.Store("a.test", "A2");
  assert(registry.size() == 2);
  const std::vector<std::string> expected{"a.test", "b.test"};
  assert(registry.HostsMostRecentFirst() == expected);

  // A zero capacity would make every store a no-op; the registry clamps to one.
  FaviconRegistry degenerate(0);
  assert(degenerate.capacity() == 1);
  degenerate.Store("a.test", "A");
  degenerate.Store("b.test", "B");
  assert(degenerate.size() == 1);
  assert(degenerate.Peek("b.test").value() == "B");
}

}  // namespace

int main() {
  TestHostKeying();
  TestIgnoresEmptyInput();
  TestEvictsLeastRecentlyUsed();
  TestRewriteKeepsCapacity();
  std::cout << "favicon registry tests passed" << std::endl;
  return 0;
}
