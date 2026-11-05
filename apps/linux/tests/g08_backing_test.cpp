#include "script_frame_compositor.h"
#include "g08_backing_observation.h"
#include <cassert>
#include <cstdlib>

int main() {
  using namespace kelpie::linuxapp;
  ScriptFrame frame{640,480,640*4,123.0,std::vector<std::uint8_t>(640*480*4,255)};
  ScriptFrameSourceSize source{640,480};
  nlohmann::json shown={{"viewportWidth",640},{"viewportHeight",480},
    {"visualViewport",{{"offsetLeft",0},{"offsetTop",0},{"width",640},{"height",480},{"scale",1}}},
    {"documentVersion","fixture-document"}};
  unsetenv("KELPIE_G08_TEST_BACKING_PATH");
  assert(ObserveG08Backing(frame,source,shown,"run",0).is_null());
  setenv("KELPIE_G08_TEST_BACKING_PATH","/unused-test-path",1);
  const auto first=ObserveG08Backing(frame,source,shown,"run",0);
  assert(first.at("roi")==nlohmann::json::array({445,190,71,71}));
  assert(first.at("bgraBase64").get<std::string>().size()==26888);
  frame.bgra[std::size_t(260)*frame.stride+515*4]=0;
  const auto second=ObserveG08Backing(frame,source,shown,"run",1);
  assert(first.at("bgraSHA256")!=second.at("bgraSHA256"));
  assert(ObserveG08Backing(frame,source,shown,"run",799).at("sequence")==799);
  bool refused=false;
  try { (void)ObserveG08Backing(frame,source,shown,"run",800); } catch (...) { refused=true; }
  assert(refused);
}
