#include "kelpie/script_presentation.h"

#include <cassert>
#include <cmath>
#include <fstream>
#include <limits>
#include <nlohmann/json.hpp>

namespace {
bool Near(double a, double b) { return std::abs(a - b) < 1e-9; }
}

int main(int argc, char** argv) {
  assert(argc == 2);
  std::ifstream file(argv[1]);
  assert(file.good());
  const auto vectors = nlohmann::json::parse(file);
  for (const auto& item : vectors.at("pointer")) {
    const KelpieScriptPoint from{item.at("from").at("x"), item.at("from").at("y")};
    const KelpieScriptPoint to{item.at("to").at("x"), item.at("to").at("y")};
    const auto point = kelpie_script_pointer_position(from, to, item.at("curve") == "s", item.at("progress"));
    assert(Near(point.x, item.at("expected").at("x")));
    assert(Near(point.y, item.at("expected").at("y")));
  }
  for (const auto& item : vectors.at("tap")) {
    const auto state = kelpie_script_tap_presentation(item.at("progress"), item.at("wobble").get<bool>(), item.at("fade").get<bool>());
    assert(Near(state.scale, item.at("expected").at("scale")));
    assert(Near(state.alpha, item.at("expected").at("alpha")));
  }
  for (const auto& item : vectors.at("timeline")) {
    assert(Near(kelpie_script_progress(item.at("elapsed"), item.at("duration")), item.at("expected")));
  }
  const auto nan = std::numeric_limits<double>::quiet_NaN();
  const auto inf = std::numeric_limits<double>::infinity();
  assert(kelpie_script_progress(nan, 100) == 0);
  assert(kelpie_script_progress(1, nan) == 0);
  assert(kelpie_script_progress(inf, 100) == 1);
  assert(kelpie_script_pointer_position({0, 0}, {10, 20}, 1, nan).x == 0);
  assert(kelpie_script_pointer_position({0, 0}, {10, 20}, 1, inf).y == 20);
}
