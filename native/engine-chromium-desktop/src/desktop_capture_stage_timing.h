#pragma once
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace kelpie {
// Diagnostic-only numeric timings. No document, URL or content is emitted.
class DesktopCaptureStageTiming {
 public:
  using Clock=std::chrono::steady_clock;
  DesktopCaptureStageTiming() {
    const char* value=std::getenv("KELPIE_CAPTURE_STAGE_DIAGNOSTICS");
    enabled_=value && std::strcmp(value,"1")==0;
  }
  Clock::time_point Now() const { return enabled_ ? Clock::now() : Clock::time_point{}; }
  void Add(double elapsed,Clock::time_point start,Clock::time_point pre,
           Clock::time_point screenshot,Clock::time_point post,Clock::time_point encoded) {
    if(!enabled_) return;
    if(rows_.size()>=800){truncated_=true;return;}
    const auto ms=[](auto a,auto b){return std::chrono::duration<double,std::milli>(b-a).count();};
    rows_.push_back({elapsed,ms(start,pre),ms(pre,screenshot),ms(screenshot,post),ms(post,encoded)});
  }
  ~DesktopCaptureStageTiming() {
    if(!enabled_) return;
    for(const auto& row:rows_) std::fprintf(stderr,"KELPIE_CAPTURE_STAGE %.3f %.3f %.3f %.3f %.3f\n",
      row.elapsed,row.pre,row.screenshot,row.post,row.encoder);
    if(truncated_) std::fputs("KELPIE_CAPTURE_STAGE_TRUNCATED\n",stderr);
  }
 private:
  struct Row { double elapsed,pre,screenshot,post,encoder; };
  bool enabled_=false,truncated_=false;
  std::vector<Row> rows_;
};
}
