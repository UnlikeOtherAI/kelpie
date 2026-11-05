#include "desktop_script_pause.h"
#include <cassert>
#include <chrono>
#include <stdexcept>
#include <string>

struct FakeClock {
  using duration=std::chrono::milliseconds; using rep=duration::rep; using period=duration::period;
  using time_point=std::chrono::time_point<FakeClock>; static constexpr bool is_steady=true;
  static inline duration elapsed{}; static time_point now() { return time_point(elapsed); }
};
int main() {
  using namespace std::chrono_literals;
  int checks=0; FakeClock::elapsed=0ms;
  kelpie::PauseDesktopScript<FakeClock>(100ms,[&] { ++checks; FakeClock::elapsed+=12ms; return false; },
    [](auto duration) { FakeClock::elapsed+=duration; });
  assert(FakeClock::elapsed>=100ms && FakeClock::elapsed<=112ms);
  assert(checks>1);
  checks=0; FakeClock::elapsed=0ms;
  kelpie::PauseDesktopScript<FakeClock>(0ms,[&] { ++checks; return true; },[](auto) { assert(false); });
  assert(checks==0);
  checks=0; FakeClock::elapsed=0ms; bool stopped=false;
  try {
    kelpie::PauseDesktopScript<FakeClock>(100ms,[&] { return ++checks==3; },
      [](auto duration) { FakeClock::elapsed+=duration; });
  } catch(const std::runtime_error& error) { stopped=std::string(error.what())=="SCRIPT_STOPPED"; }
  assert(stopped && FakeClock::elapsed==40ms);
}
