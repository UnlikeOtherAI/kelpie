// Synthetic codec history control; not evidence about a recorded browser frame.
#include "script_frame_compositor.h"
#include "script_media_encoder.h"
#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace kelpie::linuxapp;
int main(int argc,char** argv) {
  if (argc!=2) return 2;
  const std::filesystem::path root=argv[1];
  if (!std::filesystem::create_directory(root)) return 3;
  const std::array<std::array<double,15>,2> pts{{
    {{0,0.266393,0.498066,0.731110,0.945517,1.199273,1.399336,1.598874,1.866598,
      2.067556,2.295128,2.505635,2.721153,2.999615,3.206449}},
    {{0,0.265986,0.498659,0.732797,0.951810,1.199477,1.466689,1.667739,1.933402,
      2.166241,2.398606,2.599386,2.824673,3.065929,3.264412}}
  }};
  try {
    for (std::size_t timing=0;timing<pts.size();++timing) for (bool history : {false,true}) {
      const auto name=std::string(timing ? "replay-" : "original-")+(history ? "history" : "clear");
      const auto dir=root/name;
      if (!std::filesystem::create_directory(dir)) return 4;
      auto encoder=ScriptMediaEncoder::Create(dir,{"gif","mp4"},15,16777216);
      for (std::size_t i=0;i<pts[timing].size();++i) {
        const double elapsed=pts[timing][i]*1000.0;
        ScriptFrame frame{1000,702,4000,elapsed,std::vector<std::uint8_t>(1000*702*4,255)};
        if (history && i>=11 && i<14) {
          const double age=std::array<double,3>{100,350,650}[i-11];
          const nlohmann::json shown={{"elapsedMs",elapsed},{"marker",{
            {"x",92.96875},{"y",107.03125},{"radius",18.75},{"color","#F54242"},
            {"startedMs",elapsed-age},{"durationMs",700},{"wobble",true},{"fade",true}}}};
          DrawScriptOverlay(frame,shown);
        }
        if (i==14) {
          std::ofstream raw(dir/"final.bgra",std::ios::binary|std::ios::out);
          raw.write(reinterpret_cast<const char*>(frame.bgra.data()),frame.bgra.size());
          if (!raw) return 5;
        }
        if (!encoder->AddFrame(frame)) return 6;
        if (i<6 && !encoder->WriteStepPNG(frame,dir/("step-"+std::to_string(i)+".png"))) return 9;
      }
      const auto outputs=encoder->Finish(pts[timing].back()*1000.0+125.0);
      if (outputs.size()!=2) return 7;
      bool gif=false,video=false;
      for (const auto& output : outputs) {
        if (output.frame_count!=15 || output.dropped_frames!=0) return 7;
        gif |= output.mime_type=="image/gif"; video |= output.mime_type=="video/mp4";
        std::cout<<name<<" "<<output.mime_type<<" "<<output.path<<" "<<output.frame_count<<" "
                 <<output.dropped_frames<<"\n";
      }
      if (!gif || !video) return 7;
    }
  } catch (const std::exception& error) { std::cerr<<error.what()<<"\n";return 8; }
}
