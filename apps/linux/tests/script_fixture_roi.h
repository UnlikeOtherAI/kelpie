#pragma once
// Test-only fixed synthetic-fixture crop, never a general screenshot API.
#include "script_frame_compositor.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstdlib>
#include <cstdio>
#include <stdexcept>
#include <vector>

namespace kelpie::linuxapp {
inline bool FixtureRoiEnabled() { return std::getenv("KELPIE_LINUX_TEST_ROI_DIR") != nullptr; }
inline std::vector<std::uint8_t> FixtureRoi(const ScriptFrame& frame) {
  constexpr int left=70,top=85,width=45,height=45;
  if (frame.width<left+width || frame.height<top+height || frame.stride!=frame.width*4 ||
      frame.bgra.size()!=std::size_t(frame.stride)*frame.height)
    throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  std::vector<std::uint8_t> crop;crop.reserve(width*height*4);
  for(int y=top;y<top+height;++y) {
    auto begin=frame.bgra.begin()+std::size_t(y)*frame.stride+left*4;
    crop.insert(crop.end(),begin,begin+width*4);
  }
  return crop;
}
inline void WriteFixtureRoi(std::size_t index,const std::vector<std::uint8_t>& before,
                            const std::vector<std::uint8_t>& after) {
  if (!FixtureRoiEnabled()) return;
  if (index>=1200 || before.size()!=45*45*4 || after.size()!=before.size())
    throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  const char* path=std::getenv("KELPIE_LINUX_TEST_ROI_DIR");
  if (!path || path[0]!='/') throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  const int dir=open(path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  struct stat info{};
  if (dir<0 || fstat(dir,&info)!=0 || info.st_uid!=getuid() || (info.st_mode&077)!=0) {
    if(dir>=0) close(dir); throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  }
  char name[32];std::snprintf(name,sizeof(name),"sample-%04zu.bgra",index);
  const int fd=openat(dir,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);close(dir);
  if(fd<0) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
  bool ok=true;
  for(const auto* data : {&before,&after}) {
    std::size_t offset=0;while(offset<data->size()) {
      const auto count=write(fd,data->data()+offset,data->size()-offset);
      if(count<=0) {ok=false;break;} offset+=std::size_t(count);
    }
    if(!ok) break;
  }
  if(close(fd)!=0) ok=false;
  if(!ok) throw std::runtime_error("CAPTURE_TEST_OBSERVATION_FAILED");
}
}
