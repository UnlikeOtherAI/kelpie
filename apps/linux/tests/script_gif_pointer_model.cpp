// Test-only GIF controls rendered by the same compositor and writer as the app.
#include "script_frame_compositor.h"
#include "script_media_encoder.h"
#include <nlohmann/json.hpp>
#include <openssl/evp.h>
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using kelpie::linuxapp::DrawScriptOverlay;
using kelpie::linuxapp::ScriptFrame;
using kelpie::linuxapp::ScriptMediaEncoder;
using Json = nlohmann::json;
namespace fs = std::filesystem;

int main(int argc, char** argv) {
  try {
    if (argc != 3) throw std::runtime_error("Expected config JSON and new output directory");
    if (fs::file_size(argv[1]) > 65536) throw std::runtime_error("Model config too large");
    std::ifstream in(argv[1]);
    if (!in) throw std::runtime_error("Cannot read model config");
    Json config = Json::parse(in);
    const int width = config.at("width"), height = config.at("height");
    const int view_width = config.at("viewportWidth"), view_height = config.at("viewportHeight");
    const int fps = config.at("fps"), frames = config.at("frameCount");
    const double x = config.at("pointer").at("x"), y = config.at("pointer").at("y");
    const auto visual = config.at("visualViewport");
    if (width < 2 || width > 640 || height < 2 || height > 1600 ||
        view_width < 2 || view_height < 2 || fps < 1 || fps > 30 ||
        frames < 4 || frames > 60 || !std::isfinite(x) || !std::isfinite(y) ||
        x < 0 || y < 0 || x >= view_width || y >= view_height)
      throw std::runtime_error("Invalid model bounds");
    for (const char* key : {"offsetLeft", "offsetTop", "width", "height", "scale"})
      if (!visual.contains(key) || !visual[key].is_number() || !std::isfinite(visual[key].get<double>()))
        throw std::runtime_error("Invalid visual viewport");
    if (visual["width"].get<double>() <= 0 || visual["height"].get<double>() <= 0 ||
        visual["scale"].get<double>() <= 0) throw std::runtime_error("Invalid visual viewport");
    std::vector<unsigned char> backing;
    if (config.contains("backingBGRA")) {
      const auto encoded=config.at("backingBGRA").get<std::string>();
      if (encoded.empty() || encoded.size()%4 || encoded.size()>30000 || width<516 || height<261)
        throw std::runtime_error("Invalid observed backing");
      backing.resize(encoded.size()/4*3);
      const int decoded=EVP_DecodeBlock(backing.data(),reinterpret_cast<const unsigned char*>(encoded.data()),int(encoded.size()));
      const auto padding=(encoded.back()=='=')+(encoded[encoded.size()-2]=='=');
      if (decoded<0 || decoded-padding!=71*71*4) throw std::runtime_error("Invalid observed backing");
      backing.resize(decoded-padding);
    }
    const fs::path root(argv[2]);
    if (!fs::create_directory(root)) throw std::runtime_error("Output directory must be new");
    // Record live mappings before exit; the decoder hashes these independently.
    std::ifstream mappings("/proc/self/maps");
    std::ofstream mapping_output(root / "generator-maps.txt", std::ios::binary);
    if (!mappings || !mapping_output) throw std::runtime_error("Cannot record model mappings");
    mapping_output << mappings.rdbuf();
    if (!mapping_output) throw std::runtime_error("Cannot write model mappings");
    Json report = {{"version", 1}, {"input", config},
      {"encoder", {{"mimeType", "image/gif"}, {"sourcePixelFormat", "BGRA8-opaque"},
        {"palette", "RGB332-floor"}, {"maxBytes", 33554432}}},
      {"cases", Json::array()}};
    for (const std::string name : {"pointer", "small", "faint", "full", "palette-collision"}) {
      const auto dir = root / name;
      if (!fs::create_directory(dir)) throw std::runtime_error("Cannot create case directory");
      auto encoder = ScriptMediaEncoder::Create(dir, {"gif"}, fps, 33554432);
      for (int i = 0; i < frames; ++i) {
        const double elapsed = i * 1000.0 / fps;
        ScriptFrame frame{width, height, width * 4, elapsed,
          std::vector<std::uint8_t>(std::size_t(width) * height * 4, 255)};
        if (!backing.empty()) for (int row=0; row<71; ++row)
          std::copy_n(backing.data()+row*71*4,71*4,frame.bgra.data()+std::size_t(190+row)*frame.stride+445*4);
        Json shown = {{"viewportWidth", view_width}, {"viewportHeight", view_height},
          {"visualViewport", visual}, {"elapsedMs", elapsed}, {"pointer", {{"x", x}, {"y", y}}}};
        if (name != "pointer") {
          const double radius = name == "small" ? 4.0 : 48.0;
          const double age = name == "faint" ? 650.0 : name == "palette-collision" ? 699.0 : 0.0;
          shown["marker"] = {{"x", x}, {"y", y}, {"radius", radius}, {"color", "#0000FF"},
            {"startedMs", elapsed - age}, {"durationMs", 700.0}, {"wobble", false}, {"fade", true}};
        }
        DrawScriptOverlay(frame, shown);
        if (!encoder->AddFrame(frame)) throw std::runtime_error("Model frame refused");
      }
      const auto outputs = encoder->Finish(frames * 1000.0 / fps);
      if (outputs.size() != 1 || outputs[0].mime_type != "image/gif" || outputs[0].frame_count != std::size_t(frames) ||
          outputs[0].dropped_frames != 0 || encoder->budget_exceeded() || encoder->finalization_failed())
        throw std::runtime_error("Model encoder did not retain all frames");
      Json marker = nullptr;
      if (name != "pointer") marker = {{"color", "#0000FF"},
        {"radiusCss", name == "small" ? 4.0 : 48.0}, {"durationMs", 700.0},
        {"ageMs", name == "faint" ? 650.0 : name == "palette-collision" ? 699.0 : 0.0},
        {"baseAlpha", 178.0 / 255.0}, {"wobble", false}, {"fade", true}};
      report["cases"].push_back({{"name",name},{"file",outputs[0].path.string()}, {"marker",marker},
        {"frames",outputs[0].frame_count},{"durationMs",outputs[0].duration_ms}});
    }
    std::ofstream output(root / "generator.json", std::ios::binary);
    output << report.dump(2) << '\n';
    if (!output) throw std::runtime_error("Cannot write generator report");
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
