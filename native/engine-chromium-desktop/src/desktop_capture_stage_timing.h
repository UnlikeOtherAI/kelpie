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
  void Add(double elapsed,Clock::time_point start,Clock::time_point preNav,Clock::time_point pre,
           Clock::time_point screenshot,Clock::time_point postNav,Clock::time_point post,Clock::time_point encoded) {
    if(!enabled_) return;
    if(rows_.size()>=800){truncated_=true;return;}
    const auto ms=[](auto a,auto b){return std::chrono::duration<double,std::milli>(b-a).count();};
    rows_.push_back({elapsed,ms(start,preNav),ms(preNav,pre),ms(pre,screenshot),
      ms(screenshot,postNav),ms(postNav,post),ms(post,encoded)});
  }
  ~DesktopCaptureStageTiming() {
    if(!enabled_) return;
    for(const auto& row:rows_) std::fprintf(stderr,"KELPIE_CAPTURE_STAGE %.3f %.3f %.3f %.3f %.3f %.3f %.3f\n",
      row.elapsed,row.preNav,row.preViewport,row.screenshot,row.postNav,row.postViewport,row.encoder);
    if(truncated_) std::fputs("KELPIE_CAPTURE_STAGE_TRUNCATED\n",stderr);
  }
 private:
  struct Row { double elapsed,preNav,preViewport,screenshot,postNav,postViewport,encoder; };
  bool enabled_=false,truncated_=false;
  std::vector<Row> rows_;
};
}
