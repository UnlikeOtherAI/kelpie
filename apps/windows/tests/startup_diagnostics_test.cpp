#include "startup_diagnostics.h"

int main() {
  kelpie::windows::StartupDiagnostics diagnostics;
  diagnostics.Enter(kelpie::windows::StartupStage::kCefBrowser);
  diagnostics.Fail(kelpie::windows::StartupStage::kHttpListener, "The loopback listener did not bind");
  if (diagnostics.ready() || diagnostics.error() != "The loopback listener did not bind" ||
      diagnostics.Presentation().find(L"local control listener") == std::wstring::npos) return 1;
  diagnostics.Ready();
  return diagnostics.ready() && diagnostics.error().empty() && diagnostics.Presentation().empty() ? 0 : 2;
}
