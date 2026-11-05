#include "script_media_encoder.h"
#include <array>
#include <cassert>
#include <filesystem>
#include <iostream>
#include <nlohmann/json.hpp>

using namespace kelpie::linuxapp;
int main(int argc,char** argv) {
  assert(argc==2);const std::filesystem::path directory=argv[1];
  const std::array<double,15> times={0,200.259,373.026,554.832,687.314,867.401,
    1067.217,1205.603,1399.895,1555.900,1713.483,1860.141,2066.606,2267.056,2403.654};
  auto encoder=ScriptMediaEncoder::Create(directory,{"mp4"},15,8388608);
  for(std::size_t i=0;i<times.size();++i) {
    ScriptFrame frame{64,48,256,times[i],std::vector<std::uint8_t>(64*48*4,255)};
    for(std::size_t y=8;y<40;++y)for(std::size_t x=8;x<56;++x)
      frame.bgra[(y*64+x)*4+2]=std::uint8_t(100+(i*9)%155);
    assert(encoder->AddFrame(frame));
  }
  const auto outputs=encoder->Finish(2529.372);
  assert(outputs.size()==1 && outputs[0].frame_count==times.size());
  assert(!encoder->budget_exceeded() && !encoder->finalization_failed());
  for(const auto& file:std::filesystem::directory_iterator(directory)) assert(file.path()==outputs[0].path);
  std::cout<<nlohmann::json{{"file",outputs[0].path.string()},{"frames",outputs[0].frame_count},{"ptsMs",times}}.dump()<<"\n";
}
