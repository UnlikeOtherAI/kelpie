#include "kelpie/browser_gateway.h"
#include "kelpie/element_selector_script.h"
#include <iostream>
#include <string>

// Prints the actual native expressions for separate headless DOM conformance.
// This test fixture is never part of the product or its HTTP/MCP surface.
int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "--builder") {
    std::cout << kelpie::ElementSelectorBuilderScript();
    return 0;
  }
  if (argc == 2 && std::string(argv[1]) == "--snapshot") {
    std::cout << kelpie::CollectBrowserSelectorSnapshotExpression({
        {"prefix", "observed"}, {"maxElements", 150}, {"maxChars", 24000}, {"includeShadow", false}});
    return 0;
  }
  return 2;
}
