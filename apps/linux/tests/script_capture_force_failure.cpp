// Test-only terminal force failure through the real capture and artifact store.
#include "script_capture_service.h"
#include "script_frame_compositor.h"
#include "kelpie/base64.h"
#include <cassert>
#include <cstdlib>
#include <memory>
#include <vector>
using namespace kelpie;
using namespace kelpie::linuxapp;
int main() {
  auto service=std::make_shared<LinuxScriptService>([](const auto&) { return true; });
  DesktopApp::Config config;
  service->Configure(config);
  const std::string run="test-run",owner="test-owner";
  nlohmann::json options={{"formats",{"gif","video","screenshots"}},{"fps",15},{"maxWidth",128},
    {"maxBytes",16777216},{"maxDurationMs",30000}};
  auto capture=config.scripts.capture(options,run,owner);
  assert(capture->SupportsTerminalClear());
  ScriptFrame frame{128,128,512,0,std::vector<std::uint8_t>(128*128*4,255)};
  BrowserScreenshot screenshot;
  screenshot.base64_data=Base64Encode(EncodeScriptPNG(frame));
  nlohmann::json shown={{"runId",run},{"tabId","tab"},{"generation",std::uint64_t{7}},
    {"documentVersion","doc"},{"viewportWidth",128},{"viewportHeight",128},
    {"visualViewport",{{"offsetLeft",0},{"offsetTop",0},{"width",128},{"height",128},{"scale",1}}},
    {"marker",{{"actionIndex",0},{"x",64},{"y",64},{"color","#FF0000"},
      {"radius",20},{"startedMs",0},{"durationMs",100},{"wobble",true},{"fade",true}}}};
  for (int index=0;index<3;++index) {
    const double elapsed=index*100.0; shown["elapsedMs"]=elapsed;
    capture->AddFrame(screenshot,shown,elapsed,0,index==0,DesktopScriptFramePurpose::Ordinary);
  }
  shown["elapsedMs"]=300;
  capture->AddFrame(screenshot,shown,300,0,false,DesktopScriptFramePurpose::TerminalClear);
  assert(setenv("KELPIE_TEST_FORCE_FAILURE","1",1)==0);
  const auto result=capture->Finish(false,"",450);
  unsetenv("KELPIE_TEST_FORCE_FAILURE");
  assert(result.at("error")=="CAPTURE_FINALIZE_FAILED");
  bool gif=false,video=false;
  for (const auto& artifact:result.at("artifacts")) {
    assert(artifact.at("partial")==true);
    const auto mime=artifact.at("mimeType").get<std::string>();
    gif |= mime=="image/gif";video |= mime=="video/mp4";
    const auto request=nlohmann::json{{"runId",run},{"artifactId",artifact["id"]},{"offset",0},{"length",8}};
    assert(service->artifacts().Read(request,owner).value("success",false));
  }
  assert(gif && video);
  service->artifacts().Discard(run,owner);
  for (const auto& artifact:result.at("artifacts")) {
    const auto request=nlohmann::json{{"runId",run},{"artifactId",artifact["id"]},{"offset",0},{"length",8}};
    assert(!service->artifacts().Read(request,owner).value("success",false));
  }
}
