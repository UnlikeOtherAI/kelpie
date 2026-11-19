#pragma once

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>

namespace kelpie {

struct AddressLoadFrame {
  double extent = 0;
  double opacity = 0;

  bool operator==(const AddressLoadFrame& other) const {
    return extent == other.extent && opacity == other.opacity;
  }
};

class AddressLoadProgress {
 public:
  using Clock = std::chrono::steady_clock;

  void Update(bool loading, double progress, bool tab_changed, bool animate, Clock::time_point now) {
    const auto previous = Frame(now);
    if (tab_changed) *this = {};
    if (loading) {
      const double target = std::clamp(progress, 0.005, 1.0);
      if (loading_ && target == target_ && animate == animate_) return;
      from_ = loading_ && target >= target_ - 0.15 ? previous.extent : 0.005;
      target_ = target;
    } else {
      if (!loading_) return;
      from_ = previous.extent;
      target_ = progress >= 1 ? 1 : from_;
    }
    loading_ = loading;
    animate_ = animate;
    changed_ = now;
  }

  bool IsAnimating(Clock::time_point now) const {
    if (!animate_) return false;
    return loading_ ? from_ != target_ && now - changed_ < std::chrono::milliseconds(120)
                    : Frame(now).opacity > 0;
  }

  AddressLoadFrame Frame(Clock::time_point now) const {
    if (!animate_) return loading_ ? AddressLoadFrame{target_, 1} : AddressLoadFrame{};
    const auto elapsed = std::chrono::duration<double, std::milli>(now - changed_).count();
    const double t = std::clamp(elapsed / 120, 0.0, 1.0);
    const double extent = from_ + (target_ - from_) * (1 - (1 - t) * (1 - t));
    if (loading_) return {extent, 1};
    const double delay = target_ > from_ ? 120 : 0;
    return {extent, std::clamp(1 - (elapsed - delay) / 200, 0.0, 1.0)};
  }

 private:
  bool loading_ = false;
  bool animate_ = false;
  double from_ = 0;
  double target_ = 0;
  Clock::time_point changed_{};
};

// Trace the visible capsule as one path so the two arms meet cleanly at the
// left edge. The caller strokes it with a round cap and join.
template <typename AddPoint>
void TraceAddressLoadOutline(double width, double height, double stroke,
                             double extent, AddPoint add_point) {
  const double inset = stroke / 2;
  const double radius = std::min(width, height) / 2 - inset;
  if (radius <= 0 || extent <= 0) return;
  constexpr double quarter_turn = 1.5707963267948966;
  const double arc = radius * quarter_turn;
  const double left = inset + radius;
  const double right = width - left;
  const double center_y = height / 2;
  const double straight = right - left;
  const double length = (2 * arc + straight) * std::min(extent, 1.0);

  struct Point { double x, y; };
  std::array<Point, 26> upper{};
  std::size_t count = 0;
  upper[count++] = {inset, center_y};
  const auto add_arc = [&](double center_x, double start, double distance) {
    constexpr int steps = 12;
    const double sweep = std::min(distance / radius, quarter_turn);
    for (int step = 1; step <= steps; ++step) {
      const double theta = start + sweep * step / steps;
      upper[count++] = {center_x + radius * std::cos(theta), center_y + radius * std::sin(theta)};
    }
  };
  add_arc(left, 2 * quarter_turn, length);
  if (length > arc) upper[count++] = {left + std::min(length - arc, straight), center_y - radius};
  if (length > arc + straight) add_arc(right, -quarter_turn, length - arc - straight);

  for (std::size_t i = count; i > 0; --i) add_point(upper[i - 1].x, upper[i - 1].y);
  for (std::size_t i = 1; i < count; ++i) add_point(upper[i].x, height - upper[i].y);
}

}  // namespace kelpie
