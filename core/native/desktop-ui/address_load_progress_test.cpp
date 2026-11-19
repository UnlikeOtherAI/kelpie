#include "address_load_progress.h"

#include <cassert>
#include <utility>
#include <vector>

using kelpie::AddressLoadProgress;
using namespace std::chrono_literals;

int main() {
  const AddressLoadProgress::Clock::time_point start;
  AddressLoadProgress progress;
  assert(progress.Frame(start).opacity == 0);
  progress.Update(true, 0.6, false, true, start);
  assert(progress.Frame(start).extent < 0.01);
  assert(progress.Frame(start + 120ms).extent == 0.6);
  progress.Update(false, 1, false, true, start + 120ms);
  assert(progress.Frame(start + 240ms).extent == 1);
  assert(progress.Frame(start + 340ms).opacity == 0.5);
  assert(progress.Frame(start + 440ms).opacity == 0);

  progress.Update(true, 0.4, true, true, start + 500ms);
  progress.Update(false, 0.4, false, true, start + 620ms);
  assert(progress.Frame(start + 720ms).opacity == 0.5);
  assert(progress.Frame(start + 720ms).extent == 0.4);
  progress.Update(false, 1, true, true, start + 730ms);
  assert(progress.Frame(start + 730ms).opacity == 0);
  progress.Update(true, 0.3, true, false, start + 740ms);
  assert(progress.Frame(start + 740ms).extent == 0.3);
  progress.Update(false, 1, false, false, start + 750ms);
  assert(progress.Frame(start + 750ms).opacity == 0);

  std::vector<std::pair<double, double>> points;
  const auto record = [&](double x, double y) { points.emplace_back(x, y); };
  kelpie::TraceAddressLoadOutline(200, 40, 3, 0.5, record);
  assert(points[points.size() / 2] == std::make_pair(1.5, 20.0));
  assert(std::abs(points.front().first - 100) < 0.001);
  assert(points.front().second == 1.5 && points.back().second == 38.5);
  points.clear();
  kelpie::TraceAddressLoadOutline(200, 40, 3, 1, record);
  assert(std::abs(points.front().first - 198.5) < 0.001);
  assert(std::abs(points.front().second - 20) < 0.001);
  assert(std::abs(points.back().second - 20) < 0.001);
}
