#include "kelpie/history_store.h"
#include "store_support.h"

#include <cassert>
#include <iostream>
#include <string>

#include <nlohmann/json.hpp>

namespace {

void TestUrlNormalizationBugs() {
  std::cout << "Running TestUrlNormalizationBugs..." << std::endl;

  // Collapse only the implicit root slash on bare origins.
  assert(kelpie::store_support::NormalizeUrl("https://a.com/") == "https://a.com");
  assert(kelpie::store_support::NormalizeUrl("http://a.com/") == "http://a.com");

  // Resource paths must stay distinct.
  assert(kelpie::store_support::NormalizeUrl("http://a.com/b/") == "http://a.com/b/");
  assert(kelpie::store_support::NormalizeUrl("http://a.com/b//") == "http://a.com/b//");

  std::cout << "TestUrlNormalizationBugs PASSED" << std::endl;
}

void TestUrlNormalizationEdgeCases() {
    std::cout << "Running TestUrlNormalizationEdgeCases..." << std::endl;

    // Case: non-empty query, empty fragment
    assert(kelpie::store_support::NormalizeUrl("https://a.com?q=1#") == "https://a.com?q=1");

    // Case: empty query, non-empty fragment
    assert(kelpie::store_support::NormalizeUrl("https://a.com?#frag") == "https://a.com#frag");

    // Case: path with trailing slash stays unchanged
    assert(kelpie::store_support::NormalizeUrl("/a/b/") == "/a/b/");

    // Case: root path with trailing slash
    assert(kelpie::store_support::NormalizeUrl("https://a.com/") == "https://a.com");

    // Case: URL with only a scheme — "file:///" has no path, preserve the "/"
    assert(kelpie::store_support::NormalizeUrl("file:///") == "file:///");

    // Case: malformed paths with extra slashes are preserved
    assert(kelpie::store_support::NormalizeUrl("http://a.com//") == "http://a.com//");

    std::cout << "TestUrlNormalizationEdgeCases PASSED" << std::endl;
}

} // namespace

int main() {
  try {
    TestUrlNormalizationBugs();
    TestUrlNormalizationEdgeCases();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << "Tests failed: " << exception.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "Tests failed with an unknown exception." << '\n';
    return 1;
  }
}
