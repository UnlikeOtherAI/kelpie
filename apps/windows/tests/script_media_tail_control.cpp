#include "script_media_encoder.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

using namespace kelpie::windows;
namespace fs = std::filesystem;
namespace {
void Require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }

ScriptMediaFrame Fixture(bool marker) {
  ScriptMediaFrame frame{640, 406, 2560, std::vector<std::uint8_t>(640 * 406 * 4, 255), 0};
  // Static synthetic pointer and an optional red disk, both inside the same ROI.
  for (int y = 0; y < frame.height; ++y) for (int x = 0; x < frame.width; ++x) {
    const auto offset = (static_cast<std::size_t>(y) * frame.width + x) * 4;
    const int dx = x - 480, dy = y - 203;
    if (marker && dx * dx + dy * dy <= 25 * 25) {
      frame.bgra[offset] = 77; frame.bgra[offset + 1] = 77; frame.bgra[offset + 2] = 255;
    }
    if (x >= 480 && x < 486 && y >= 203 && y < 216) {
      frame.bgra[offset] = frame.bgra[offset + 1] = frame.bgra[offset + 2] = 0;
    }
  }
  return frame;
}
void WriteRaw(const fs::path& path, const ScriptMediaFrame& frame) {
  std::ofstream output(path, std::ios::binary);
  Require(output.is_open(), "RAW_OPEN");
  output.write(reinterpret_cast<const char*>(frame.bgra.data()), static_cast<std::streamsize>(frame.bgra.size()));
  Require(output.good(), "RAW_WRITE");
}
void Case(const fs::path& root, const char* name, bool marker,
          const ScriptMediaFrame& clean, const ScriptMediaFrame& marked) {
  const auto path = root / name;
  Require(fs::create_directory(path), "CASE_DIRECTORY");
  auto writer = ScriptMediaEncoder::Create(path, {"gif", "mp4"}, 20, 32 * 1024 * 1024);
  for (int index = 0; index < 40; ++index) {
    auto frame = marker && index >= 10 && index < 30 ? marked : clean;
    frame.elapsed_ms = index * 50.0;
    Require(writer->AddFrame(frame), "FRAME_REFUSED");
  }
  const auto outputs = writer->Finish(2000);
  Require(outputs.size() == 2, "FORMAT_MISSING");
  for (const auto& output : outputs) {
    Require(output.width == 640 && output.height == 406 && output.frame_count == 40 && output.dropped_frames == 0,
            "OUTPUT_METADATA");
  }
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    Require(argc == 2, "EXPECTED_FRESH_DIRECTORY");
    const fs::path root(argv[1]);
    Require(!fs::exists(root) && fs::create_directories(root), "DIRECTORY_EXISTS");
    const auto clean = Fixture(false), marked = Fixture(true);
    Require(clean.bgra != marked.bgra, "MARKER_MISSING");
    WriteRaw(root / "clean.bgra", clean);
    WriteRaw(root / "marked.bgra", marked);
    Case(root, "clean-only", false, clean, marked);
    Case(root, "marker-then-clean", true, clean, marked);
    std::cout << "40 frames per case; 20 fps; 10 clean, 20 marker-or-clean, 10 clean\n";
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
