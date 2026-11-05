// Isolated test executable: observes renderer context release, never changes the app.
#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_render_handler.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"
#include <nlohmann/json.hpp>
#include <cstdlib>
#include <iostream>
#include <string>

using Json = nlohmann::json;
class ProofApp final : public CefApp, public CefRenderProcessHandler {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
  void OnBeforeCommandLineProcessing(const CefString&, CefRefPtr<CefCommandLine> command) override {
    command->AppendSwitch("disable-gpu");
    command->AppendSwitch("disable-gpu-compositing");
    command->AppendSwitchWithValue("ozone-platform", "headless");
  }
  void OnContextReleased(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         CefRefPtr<CefV8Context> context) override {
    const char* nonce = std::getenv("KELPIE_RELEASE_PROOF_NONCE");
    if (!nonce || std::string(nonce).find_first_not_of("0123456789abcdef") != std::string::npos) return;
    Json output = {{"type","context-released"},{"browserId",browser->GetIdentifier()},
      {"frameId",frame->GetIdentifier()},{"mainFrame",frame->IsMain()},{"contextValid",context->IsValid()}};
    if (context->IsValid() && context->Enter()) {
      CefRefPtr<CefV8Value> value; CefRefPtr<CefV8Exception> exception;
      const std::string key = "__kelpie_release_proof_" + std::string(nonce);
      const std::string sentinel = "__kelpie_release_nonce_" + std::string(nonce);
      const std::string script = "JSON.stringify({nonceMatch:globalThis[" + Json(sentinel).dump() + "]===" +
        Json(nonce).dump() + ",token:Object.keys(globalThis[" + Json(key).dump() + "]?.entries||{})[0]||null,url:location.href,before:document.body?.dataset.before||null,"
        "after:document.body?.dataset.after||null,password:document.querySelector('#edit')?.type||null})";
      const bool ok = context->Eval(script, "", 0, value, exception);
      output["evalOK"] = ok;
      if (ok && value && value->IsString()) {
        auto parsed = Json::parse(value->GetStringValue().ToString(), nullptr, false);
        if (!parsed.is_discarded()) {
          output["observation"] = parsed;
          if (parsed.value("nonceMatch", false) && parsed.contains("token") && parsed["token"].is_string()) {
            Json options = {{"target",{{"selector","#edit"}}},{"key",key},{"token",parsed["token"]},
              {"postMutation",true},{"policy",{{"refuseSensitive",true}}}};
            char* raw = kelpie_browser_script_target_expression(options.dump().c_str());
            if (raw) {
              Json generated = Json::parse(raw, nullptr, false); kelpie_mcp_free_string(raw);
              if (!generated.is_discarded() && generated.contains("expression")) {
                CefRefPtr<CefV8Value> classification; CefRefPtr<CefV8Exception> failure;
                const bool classified = context->Eval(generated["expression"].get<std::string>(), "", 0, classification, failure);
                output["classificationEvalOK"] = classified;
                if (classified && classification && classification->IsObject()) {
                  const auto as_json = classification->GetValue("ok");
                  const auto sensitive = classification->GetValue("sensitive");
                  const auto known = classification->GetValue("sensitivityKnown");
                  if (as_json && sensitive && known && as_json->IsBool() && sensitive->IsBool() && known->IsBool())
                    output["classification"] = {{"ok",as_json->GetBoolValue()},
                      {"sensitive",sensitive->GetBoolValue()},{"sensitivityKnown",known->GetBoolValue()}};
                }
              }
            }
          }
        }
      } else if (exception) output["exception"] = exception->GetMessage().ToString();
      context->Exit();
    }
    std::cerr << "KELPIE_RELEASE_PROOF " << output.dump() << std::endl;
  }
 private:
  IMPLEMENT_REFCOUNTING(ProofApp);
};
class ProofClient final : public CefClient, public CefRenderHandler, public CefLifeSpanHandler {
 public:
  CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  void GetViewRect(CefRefPtr<CefBrowser>, CefRect& rect) override { rect = CefRect(0,0,640,480); }
  void OnPaint(CefRefPtr<CefBrowser>, PaintElementType, const RectList&, const void*, int, int) override {}
  void OnBeforeClose(CefRefPtr<CefBrowser>) override { CefQuitMessageLoop(); }
 private:
  IMPLEMENT_REFCOUNTING(ProofClient);
};
int main(int argc, char** argv) {
  CefMainArgs args(argc,argv);
  CefRefPtr<ProofApp> app = new ProofApp();
  const int child = CefExecuteProcess(args,app,nullptr);
  if (child >= 0) return child;
  const char* url = std::getenv("KELPIE_RELEASE_PROOF_URL");
  const char* port = std::getenv("KELPIE_RELEASE_PROOF_PORT");
  if (!url || !port) return 2;
  CefSettings settings;
  settings.no_sandbox = false;
  settings.windowless_rendering_enabled = true;
  settings.remote_debugging_port = std::atoi(port);
  if (!CefInitialize(args,settings,app,nullptr)) return 3;
  CefWindowInfo window; window.SetAsWindowless(0);
  CefBrowserSettings browser_settings;
  CefRefPtr<ProofClient> client = new ProofClient();
  auto browser = CefBrowserHost::CreateBrowserSync(window,client,url,browser_settings,nullptr,nullptr);
  if (!browser) { CefShutdown(); return 4; }
  CefRunMessageLoop();
  browser = nullptr; client = nullptr; app = nullptr;
  CefShutdown();
  return 0;
}
