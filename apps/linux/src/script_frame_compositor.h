#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {
struct ScriptFrame {
  int width = 0, height = 0, stride = 0;
  double elapsed_ms = 0;
  std::vector<std::uint8_t> bgra;
};
ScriptFrame DecodeScriptFrame(const std::string& png_base64, int max_width, double elapsed_ms);
// The GTK viewport and exported frame use this exact native presentation path.
void DrawScriptOverlay(ScriptFrame& frame, const nlohmann::json& presentation);
std::vector<std::uint8_t> EncodeScriptPNG(const ScriptFrame& frame);
}
