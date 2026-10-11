#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/browser_gateway.h"
#include <cstdlib>
#include <cstring>
#include <mutex>
struct KelpieBrowserGateway {
  explicit KelpieBrowserGateway(nlohmann::json config) : gateway(std::move(config)) {}
  kelpie::BrowserGateway gateway;
  std::mutex mutex;
};
namespace {
char* Copy(const nlohmann::json& value) {
  const std::string text = value.dump();
  char* output = static_cast<char*>(std::malloc(text.size() + 1));
  if (output) std::memcpy(output, text.c_str(), text.size() + 1);
  return output;
}
nlohmann::json Parse(const char* input, std::size_t limit = 131072) {
  if (!input || std::strlen(input) > limit) return nullptr;
  return nlohmann::json::parse(input, nullptr, false);
}
template <typename Action> char* Invoke(KelpieBrowserGatewayRef gateway, Action action) {
  if (!gateway) return nullptr;
  std::lock_guard<std::mutex> lock(gateway->mutex);
  try { return Copy(action(gateway->gateway)); } catch (...) { return Copy(gateway->gateway.Cancel()); }
}
}
extern "C" {
KelpieBrowserGatewayRef kelpie_browser_gateway_create(const char* config) {
  try {
    const auto value = Parse(config);
    if (!value.is_object()) return nullptr;
    return new KelpieBrowserGateway(value);
  } catch (...) { return nullptr; }
}
void kelpie_browser_gateway_invalidate_refs(KelpieBrowserGatewayRef gateway, const char* tab_id) {
  if (!gateway) return;
  std::lock_guard<std::mutex> lock(gateway->mutex);
  gateway->gateway.InvalidateReferences(tab_id ? tab_id : "");
}
void kelpie_browser_gateway_destroy(KelpieBrowserGatewayRef gateway) { delete gateway; }
char* kelpie_browser_gateway_begin(KelpieBrowserGatewayRef gateway, const char* request) {
  return Invoke(gateway, [&](auto& control) { return control.Begin(Parse(request)); });
}
char* kelpie_browser_gateway_begin_mcp(KelpieBrowserGatewayRef gateway, const char* request) {
  return Invoke(gateway, [&](auto& control) { return control.BeginMcp(Parse(request)); });
}
char* kelpie_browser_gateway_next(KelpieBrowserGatewayRef gateway) { return Invoke(gateway, [](auto& control) { return control.Next(); }); }
char* kelpie_browser_gateway_advance(KelpieBrowserGatewayRef gateway, const char* result) {
  return Invoke(gateway, [&](auto& control) { return control.Advance(Parse(result, 32 * 1024 * 1024)); });
}
char* kelpie_browser_gateway_cancel(KelpieBrowserGatewayRef gateway) { return Invoke(gateway, [](auto& control) { return control.Cancel(); }); }
}
