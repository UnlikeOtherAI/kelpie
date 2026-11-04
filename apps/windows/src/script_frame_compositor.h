#pragma once
#include "script_media_encoder.h"
#include <nlohmann/json.hpp>
#include <string>
namespace kelpie::windows {
ScriptMediaFrame DecodeScriptFrame(const std::string& png_base64, int max_width, double elapsed_ms);
void DrawScriptOverlay(ScriptMediaFrame& frame, const nlohmann::json& presentation);
}
