// Test-only forced-IDR failure must retain valid earlier movie prefixes.
#include "script_media_encoder.h"
#include <algorithm>
#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <vector>
using namespace kelpie::linuxapp;
int main(int argc,char** argv) {
  assert(argc==2);
  const std::filesystem::path directory=argv[1];
  assert(std::filesystem::create_directory(directory));
  auto encoder=ScriptMediaEncoder::Create(directory,{"gif","mp4"},15,16777216);
  ScriptFrame frame{128,128,512,0,std::vector<std::uint8_t>(128*128*4,255)};
  for (int index=0;index<4;++index) {
    frame.elapsed_ms=index*100;
    assert(encoder->AddFrame(frame));
  }
  assert(encoder->MarkTerminalClear(frame));
  assert(setenv("KELPIE_TEST_FORCE_FAILURE","1",1)==0);
  const auto outputs=encoder->Finish(450);
  unsetenv("KELPIE_TEST_FORCE_FAILURE");
  assert(encoder->finalization_failed());
  bool gif=false,video=false;
  for (const auto& output:outputs) {
    assert(std::filesystem::file_size(output.path)>0);
    if (output.mime_type=="image/gif") { gif=true; assert(output.frame_count==4); }
    if (output.mime_type=="video/mp4") { video=true; assert(output.frame_count==3 && output.dropped_frames==1); }
  }
  assert(gif && video);
}
