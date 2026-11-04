#include "kelpie/script_presentation.h"

#include <algorithm>
#include <cmath>

namespace {
double ClampProgress(double progress) {
  return std::isnan(progress) ? 0.0 : std::clamp(progress, 0.0, 1.0);
}
}

extern "C" double kelpie_script_progress(double elapsed_ms, double duration_ms) {
  if (std::isnan(duration_ms)) return 0.0;
  return duration_ms <= 0.0 ? 1.0 : ClampProgress(elapsed_ms / duration_ms);
}

extern "C" KelpieScriptPoint kelpie_script_pointer_position(
    KelpieScriptPoint from, KelpieScriptPoint to, int curve_s, double progress) {
  const double raw = ClampProgress(progress);
  const double t = raw * raw * (3.0 - 2.0 * raw);
  const double dx = to.x - from.x, dy = to.y - from.y;
  const double distance = std::hypot(dx, dy);
  const double amplitude = std::min(80.0, distance * 0.18);
  const double nx = distance > 0.0 ? -dy / distance * amplitude : 0.0;
  const double ny = distance > 0.0 ? dx / distance * amplitude : 0.0;
  const double sign = curve_s != 0 ? -1.0 : 1.0;
  const KelpieScriptPoint a{from.x + dx / 3.0 + nx, from.y + dy / 3.0 + ny};
  const KelpieScriptPoint b{from.x + dx * 2.0 / 3.0 + nx * sign,
                           from.y + dy * 2.0 / 3.0 + ny * sign};
  const double u = 1.0 - t;
  return {u * u * u * from.x + 3.0 * u * u * t * a.x +
              3.0 * u * t * t * b.x + t * t * t * to.x,
          u * u * u * from.y + 3.0 * u * u * t * a.y +
              3.0 * u * t * t * b.y + t * t * t * to.y};
}

extern "C" KelpieScriptTapState kelpie_script_tap_presentation(
    double progress, int wobble, int fade) {
  constexpr double pi = 3.141592653589793238462643383279502884;
  const double t = ClampProgress(progress);
  return {wobble != 0 ? 1.0 + 0.12 * std::sin(6.0 * pi * t) * (1.0 - t) : 1.0,
          fade != 0 ? 1.0 - t : (t < 1.0 ? 1.0 : 0.0)};
}
