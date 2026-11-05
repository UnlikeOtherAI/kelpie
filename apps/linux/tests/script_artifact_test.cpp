#include "script_artifact_store.h"
#include "script_frame_compositor.h"
#include "script_media_encoder.h"
#include <openssl/evp.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cassert>
#include <filesystem>
#include <iostream>
#include <stdexcept>

using namespace kelpie::linuxapp;
namespace {
std::vector<std::uint8_t> Decode(const std::string& text) {
  if (text.empty()) return {};
  std::vector<std::uint8_t> bytes(text.size() / 4 * 3);
  const auto size = EVP_DecodeBlock(bytes.data(), reinterpret_cast<const unsigned char*>(text.data()), text.size());
  assert(size >= 0);
  bytes.resize(size - (text.back() == '=') - (text[text.size() - 2] == '=')); return bytes;
}
std::vector<std::uint8_t> PNG() {
  ScriptFrame frame{32, 32, 128, 0, std::vector<std::uint8_t>(32 * 32 * 4, 255)};
  return EncodeScriptPNG(frame);
}
}
int main() {
  const auto directory = CreatePrivateCaptureDirectory();
  struct stat mode{}; assert(stat(directory.c_str(), &mode) == 0 && (mode.st_mode & 0777) == 0700);
  const auto bytes = PNG();
  const auto path = directory / "step.png";
  WriteCaptureFile(path, bytes);
  assert(stat(path.c_str(), &mode) == 0 && (mode.st_mode & 0777) == 0600);
  bool exists = false;
  try { WriteCaptureFile(path, {1, 2, 3}); }
  catch (const std::runtime_error& error) { exists = std::string(error.what()) == "CAPTURE_OUTPUT_EXISTS"; }
  assert(exists);
  const auto alias = directory / "alias.png"; std::filesystem::create_symlink(path, alias);
  bool symlink = false;
  try { WriteCaptureFile(alias, {4, 5}); } catch (...) { symlink = true; }
  assert(symlink && std::filesystem::is_symlink(alias)); std::filesystem::remove(alias);
  {
    ScriptArtifactStore store;
    const auto manifest = store.Publish(path, "image/png", {{"width", 32}, {"height", 32}}, "run", "owner");
    assert(manifest["byteLength"] == bytes.size() && manifest["sha256"].get<std::string>().size() == 64);
    auto request = nlohmann::json{{"runId", "run"}, {"artifactId", manifest["id"]}, {"length", 7}};
    assert(store.Read(request, "foreign")["error"]["code"] == "ARTIFACT_NOT_FOUND");
    auto other = request; other["runId"] = "foreign";
    assert(store.Read(other, "owner")["error"]["code"] == "ARTIFACT_NOT_FOUND");
    for (const auto& invalid : {nlohmann::json(-1), nlohmann::json(1.5), nlohmann::json("1")}) {
      auto malformed = request; malformed["offset"] = invalid;
      assert(store.Read(malformed, "owner")["error"]["code"] == "INVALID_PARAMS");
    }
    auto oversized = request; oversized["length"] = 1048577;
    assert(store.Read(oversized, "owner")["error"]["code"] == "INVALID_PARAMS");
    std::vector<std::uint8_t> downloaded; std::uint64_t offset = 0;
    while (true) {
      request["offset"] = offset; const auto result = store.Read(request, "owner");
      assert(result["success"] == true && result["sha256"] == manifest["sha256"]);
      const auto chunk = Decode(result["data"].get<std::string>());
      downloaded.insert(downloaded.end(), chunk.begin(), chunk.end());
      offset = result["nextOffset"].get<std::uint64_t>();
      if (result["eof"] == true) break;
    }
    assert(downloaded == bytes && offset == bytes.size());
    // A replaced inode cannot reuse an existing opaque artifact grant.
    const auto replacement = directory / "replacement.png";
    WriteCaptureFile(replacement, bytes); std::filesystem::rename(replacement, path);
    assert(store.Read(request, "owner")["error"]["code"] == "ARTIFACT_READ_FAILED");
  }
  assert(!std::filesystem::exists(path)); std::filesystem::remove(directory);

  const auto budget_dir = CreatePrivateCaptureDirectory();
  auto encoder = ScriptMediaEncoder::Create(budget_dir, {}, 10, 1024);
  ScriptFrame frame{32, 32, 128, 0, std::vector<std::uint8_t>(32 * 32 * 4, 255)};
  std::vector<std::filesystem::path> kept; bool stopped = false; std::uintmax_t total = 0;
  for (int index = 0; index < 100; ++index) {
    const auto output = budget_dir / ("step-" + std::to_string(index) + ".png");
    if (!encoder->WriteStepPNG(frame, output)) {
      assert(!std::filesystem::exists(output)); stopped = true; break;
    }
    kept.push_back(output); total += std::filesystem::file_size(output);
  }
  assert(stopped && !kept.empty() && total <= 1024 && encoder->budget_exceeded());
  assert(encoder->Finish(0).empty() && !encoder->finalization_failed());
  for (const auto& output : kept) std::filesystem::remove(output);
  std::filesystem::remove(budget_dir);
  std::cout << nlohmann::json{{"mode", "0700/0600"}, {"ownerChunks", true}, {"inodeFence", true},
      {"pngBudgetBytes", 1024}, {"actualPNGBytes", total}, {"retainedPNGs", kept.size()}}.dump(2) << std::endl;
}
