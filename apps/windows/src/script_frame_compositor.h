#pragma once
#include "script_media_encoder.h"
#include <nlohmann/json.hpp>
#include <string>
namespace kelpie::windows {
struct ScriptFrameSourceSize { int width=0,height=0; };
ScriptMediaFrame DecodeScriptFrame(const std::string& png_base64, int max_width, double elapsed_ms, ScriptFrameSourceSize* source_size=nullptr);
void DrawScriptOverlay(ScriptMediaFrame& frame, const nlohmann::json& presentation);
}
