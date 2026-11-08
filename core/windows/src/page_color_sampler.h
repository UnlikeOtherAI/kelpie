#pragma once

#include <future>
#include <optional>
#include "kelpie/desktop_browser_control.h"
#include "theme/chrome_palette.h"

namespace kelpie::windows {

// Exactly one bounded request; owned and drained before the engine is destroyed.
class PageColorSampler {
 public:
  std::optional<COLORREF> Poll(DesktopBrowserControl& engine, const TabSnapshot& tab,
                                std::uint64_t now);
  bool Drain();
 private:
  struct Result {
    std::uint64_t epoch;
    std::string url;
    std::optional<COLORREF> color;
  };
  std::future<Result> pending_;
  std::string tab_id_, url_;
  std::uint64_t generation_ = 0, epoch_ = 0, next_sample_ = 0;
  bool loading_ = false;
};

}  // namespace kelpie::windows
