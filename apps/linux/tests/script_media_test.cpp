#include "script_frame_compositor.h"
#include "script_media_encoder.h"
#include "script_artifact_store.h"
#include "script_gstreamer.h"
#include "kelpie/base64.h"
#include <gif_lib.h>
#include <algorithm>
#include <cassert>
#include <cmath>
#include <stdexcept>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>

using namespace kelpie::linuxapp;
namespace {
ScriptFrame Frame(int index, int width = 64, int height = 48) {
  ScriptFrame value{width, height, width * 4, index * 100.0, {}};
  value.bgra.assign(std::size_t(value.stride) * height, 255);
  DrawScriptOverlay(value, {{"elapsedMs", value.elapsed_ms}, {"marker",
      {{"x", width / 2.0}, {"y", height / 2.0}, {"radius", 8}, {"color", "#FF0000"},
       {"startedMs", value.elapsed_ms}, {"durationMs", 700}, {"wobble", false}, {"fade", false}}}});
  return value;
}
std::vector<std::uint8_t> Bytes(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  assert(input); return {std::istreambuf_iterator<char>(input), {}};
}
std::size_t DecodeGif(const ScriptMediaOutput& output) {
  int error = 0; auto* gif = DGifOpenFileName(output.path.c_str(), &error);
  assert(gif && DGifSlurp(gif) == GIF_OK);
  assert(gif->SWidth == output.width && gif->SHeight == output.height);
  std::uint64_t duration = 0;
  for (int index = 0; index < gif->ImageCount; ++index) {
    const auto& image = gif->SavedImages[index]; assert(image.RasterBits);
    assert(image.ImageDesc.Width == output.width && image.ImageDesc.Height == output.height);
    const auto* palette = image.ImageDesc.ColorMap ? image.ImageDesc.ColorMap : gif->SColorMap;
    assert(palette);
    const auto pixel = image.RasterBits[(output.height / 2) * output.width + output.width / 2];
    assert(pixel < palette->ColorCount);
    const auto color = palette->Colors[pixel];
    assert(color.Red > 200 && color.Green < 120 && color.Blue < 120);
    GraphicsControlBlock control{}; assert(DGifSavedExtensionToGCB(gif, index, &control) == GIF_OK);
    duration += control.DelayTime * 10;
  }
  const auto count = std::size_t(gif->ImageCount); assert(DGifCloseFile(gif, &error) == GIF_OK);
  assert(count == output.frame_count && duration == std::uint64_t(output.duration_ms));
  return count;
}
std::size_t DecodeVideo(const ScriptMediaOutput& output) {
  using kelpie::linuxapp::media::GstPipeline;
  GstPipeline pipeline("appsrc name=input format=bytes is-live=false block=false ! qtdemux ! "
      "h264parse ! openh264dec ! videoconvert ! video/x-raw,format=BGRA ! "
      "appsink name=output sync=false async=false max-buffers=2");
  auto* caps = gst_caps_new_simple("video/quicktime", "variant", G_TYPE_STRING, "iso", nullptr);
  gst_app_src_set_caps(pipeline.source(), caps); gst_caps_unref(caps); pipeline.Start();
  const auto bytes = Bytes(output.path);
  auto* buffer = gst_buffer_new_allocate(nullptr, bytes.size(), nullptr); assert(buffer);
  assert(gst_buffer_fill(buffer, 0, bytes.data(), bytes.size()) == bytes.size());
  pipeline.Push(buffer); assert(gst_app_src_end_of_stream(pipeline.source()) == GST_FLOW_OK);
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(15);
  std::size_t count = 0;
  while (std::chrono::steady_clock::now() < deadline) {
    auto* sample = gst_app_sink_try_pull_sample(pipeline.sink(), 100 * GST_MSECOND);
    if (!sample) { if (gst_app_sink_is_eos(pipeline.sink())) break; continue; }
    auto* frame = gst_sample_get_buffer(sample); auto* info = gst_caps_get_structure(gst_sample_get_caps(sample), 0);
    int width = 0, height = 0;
    assert(gst_structure_get_int(info, "width", &width) && gst_structure_get_int(info, "height", &height));
    assert(width == output.width && height == output.height);
    GstMapInfo mapped{}; assert(gst_buffer_map(frame, &mapped, GST_MAP_READ));
    assert(mapped.size >= std::size_t(width) * height * 4);
    const auto* pixel = mapped.data + ((height / 2) * width + width / 2) * 4;
    assert(pixel[2] > 180 && pixel[0] < 140 && pixel[1] < 140);
    assert(GST_BUFFER_PTS_IS_VALID(frame));
    assert(std::abs(double(GST_BUFFER_PTS(frame)) / GST_MSECOND - count * 100.0) < 2);
    gst_buffer_unmap(frame, &mapped); gst_sample_unref(sample); ++count;
  }
  assert(gst_app_sink_is_eos(pipeline.sink()));
  assert(count == output.frame_count && count > 0); return count;
}

void HeldMarker() {
  ScriptFrame frame{64, 48, 256, 100, std::vector<std::uint8_t>(64 * 48 * 4, 255)};
  nlohmann::json shown{{"elapsedMs", 100}, {"marker", {{"x", 32}, {"y", 24},
      {"radius", 8}, {"color", "#FF0000"}, {"startedMs", 1000},
      {"durationMs", 700}, {"wobble", false}, {"fade", false}}}};
  DrawScriptOverlay(frame, shown);
  const auto center = (24 * 64 + 32) * 4;
  assert(frame.bgra[center + 2] > 200 && frame.bgra[center] < 120);
  frame.bgra.assign(frame.bgra.size(), 255); shown["elapsedMs"] = 2000;
  DrawScriptOverlay(frame, shown);
  assert(frame.bgra[center] == 255 && frame.bgra[center + 2] == 255);
}

void VisualViewportPixels() {
  const auto blank = [] { return ScriptFrame{200, 200, 800, 0, std::vector<std::uint8_t>(200 * 200 * 4, 255)}; };
  const auto bounds = [](const ScriptFrame& frame, int x, int y, int diameter) {
    int left = frame.width, right = -1, top = frame.height, bottom = -1;
    for (int row = 0; row < frame.height; ++row) for (int column = 0; column < frame.width; ++column) {
      const auto* pixel = frame.bgra.data() + (row * frame.width + column) * 4;
      if (pixel[2] > 200 && pixel[1] < 150 && pixel[0] < 150) {
        left = std::min(left, column); right = std::max(right, column);
        top = std::min(top, row); bottom = std::max(bottom, row);
      }
    }
    assert(right > left && bottom > top);
    assert(std::abs((left + right) / 2.0 - x) <= 1 && std::abs((top + bottom) / 2.0 - y) <= 1);
    assert(std::abs(right - left + 1 - diameter) <= 2 && std::abs(bottom - top + 1 - diameter) <= 2);
  };
  nlohmann::json shown{{"viewportWidth", 100}, {"viewportHeight", 100}, {"elapsedMs", 0},
      {"marker", {{"x", 25}, {"y", 25}, {"radius", 10}, {"color", "#FF0000"},
          {"startedMs", 0}, {"durationMs", 700}, {"wobble", false}, {"fade", false}}}};
  auto baseline = blank(); DrawScriptOverlay(baseline, shown); bounds(baseline, 50, 50, 40);
  shown["visualViewport"] = {{"offsetLeft", 10}, {"offsetTop", 5}, {"width", 50}, {"height", 50}, {"scale", 2}};
  auto zoomed = blank(); DrawScriptOverlay(zoomed, shown); bounds(zoomed, 60, 80, 80);
  shown["visualViewport"] = {{"offsetLeft", 0}, {"offsetTop", 0}, {"width", 90}, {"height", 90}, {"scale", 1}};
  auto gutter = blank(); DrawScriptOverlay(gutter, shown); assert(gutter.bgra == baseline.bgra);
  shown.erase("marker");
  shown["commentary"] = {{"text", "Native capture"}, {"position", "top"}, {"startedMs", 0}, {"durationMs", 1000}};
  auto note = blank(); DrawScriptOverlay(note, shown);
  shown["visualViewport"] = {{"offsetLeft", 10}, {"offsetTop", 5}, {"width", 50}, {"height", 50}, {"scale", 2}};
  auto panned_note = blank(); DrawScriptOverlay(panned_note, shown); assert(note.bgra == panned_note.bgra);
  shown["visualViewport"]["scale"] = 0;
  bool refused = false;
  try { DrawScriptOverlay(panned_note, shown); }
  catch (const std::runtime_error& error) { refused = std::string(error.what()) == "CAPTURE_VIEWPORT_CHANGED"; }
  assert(refused);
}

void PNG() {
  auto frame = Frame(0);
  const auto png = EncodeScriptPNG(frame);
  ScriptFrameSourceSize source;
  auto scaled = DecodeScriptFrame(kelpie::Base64Encode(png), 32, 10, &source);
  assert(source.width == 64 && source.height == 48);
  const auto alternate_png = EncodeScriptPNG(Frame(0, 65, 49));
  auto alternate = DecodeScriptFrame(kelpie::Base64Encode(alternate_png), 32, 10, &source);
  assert(source.width == 65 && source.height == 49);
  assert(alternate.width == scaled.width && alternate.height == scaled.height);
  assert(scaled.width == 32 && scaled.height == 24 && scaled.elapsed_ms == 10);
  const auto center = (scaled.height / 2 * scaled.width + scaled.width / 2) * 4;
  assert(scaled.bgra[center + 2] > 200 && scaled.bgra[center] < 120);
  auto large = png; large[16] = 0x7f; large[17] = large[18] = large[19] = 0xff;
  bool rejected = false;
  try { DecodeScriptFrame(kelpie::Base64Encode(large), 32, 0); }
  catch (const std::runtime_error& error) { rejected = std::string(error.what()) == "CAPTURE_FRAME_TOO_LARGE"; }
  assert(rejected);
}
}
int main() {
  PNG(); HeldMarker(); VisualViewportPixels();
  const auto directory = CreatePrivateCaptureDirectory();
  const auto info = media::ScriptGstRuntimeInfo();
  auto encoder = ScriptMediaEncoder::Create(directory, {"gif", "mp4"}, 10, 1048576);
  assert(encoder->committed_movie_frames() == 0);
  for (int index = 0; index < 5; ++index) {
    assert(encoder->AddFrame(Frame(index)));
    assert(encoder->committed_movie_frames() == std::size_t(index));
  }
  const auto outputs = encoder->Finish(500);
  assert(!encoder->budget_exceeded() && !encoder->finalization_failed() && outputs.size() == 2);
  std::uintmax_t total = 0;
  nlohmann::json report{{"runtime", info}, {"outputs", nlohmann::json::array()}};
  for (const auto& output : outputs) {
    total += std::filesystem::file_size(output.path);
    const auto count = output.mime_type == "image/gif" ? DecodeGif(output) : DecodeVideo(output);
    assert(count == 5 && output.duration_ms == 500);
    report["outputs"].push_back({{"mime", output.mime_type}, {"decodedFrames", count},
        {"durationMs", output.duration_ms}, {"bytes", std::filesystem::file_size(output.path)}});
  }
  assert(total <= 1048576 && encoder->committed_movie_frames() == 5);
  assert(encoder->Finish(500).size() == outputs.size());
  const auto limited_dir = CreatePrivateCaptureDirectory();
  auto limited = ScriptMediaEncoder::Create(limited_dir, {"gif"}, 10, 2200);
  bool stopped = false; int index = 0;
  for (; index < 200; ++index) if (!limited->AddFrame(Frame(index, 32, 32))) { stopped = true; break; }
  assert(stopped && limited->budget_exceeded());
  const auto partial = limited->Finish((index + 1) * 100.0);
  assert(partial.size() == 1 && partial[0].frame_count > 0 && partial[0].frame_count < 200);
  assert(std::filesystem::file_size(partial[0].path) <= 2200);
  report["budgetPrefix"] = {{"decodedFrames", DecodeGif(partial[0])}, {"limitBytes", 2200},
      {"actualBytes", std::filesystem::file_size(partial[0].path)}};

  const auto video_dir = CreatePrivateCaptureDirectory();
  auto video = ScriptMediaEncoder::Create(video_dir, {"mp4"}, 10, 90000);
  stopped = false;
  for (index = 0; index < 200; ++index) if (!video->AddFrame(Frame(index))) { stopped = true; break; }
  assert(stopped && video->budget_exceeded());
  const auto retained = video->committed_movie_frames();
  const auto video_prefix = video->Finish((index + 1) * 100.0);
  assert(video_prefix.size() == 1 && retained > 0 && video_prefix[0].frame_count == retained);
  assert(!video->finalization_failed() && std::filesystem::file_size(video_prefix[0].path) <= 90000);
  report["videoBudgetPrefix"] = {{"decodedFrames", DecodeVideo(video_prefix[0])}, {"limitBytes", 90000},
      {"actualBytes", std::filesystem::file_size(video_prefix[0].path)}, {"committedPrefix", retained}};
  for (const auto& output : video_prefix) std::filesystem::remove(output.path);
  std::filesystem::remove(video_dir);

  const auto fault_dir = CreatePrivateCaptureDirectory();
  auto fault = ScriptMediaEncoder::Create(fault_dir, {"gif", "mp4"}, 10, 1048576);
  assert(fault->AddFrame(Frame(0)) && fault->AddFrame(Frame(1)));
  assert(fault->committed_movie_frames() == 1); // Actual picture retained by both writers.
  std::ofstream(fault_dir / "capture.mp4") << "owned finalization collision";
  const auto survived = fault->Finish(200);
  assert(fault->finalization_failed() && survived.size() == 1 && survived[0].mime_type == "image/gif");
  assert(DecodeGif(survived[0]) == 2);
  report["postAckFinalizeFailure"] = {{"failed", true}, {"retainedGifFrames", survived[0].frame_count}};
  for (const auto& output : survived) std::filesystem::remove(output.path);
  std::filesystem::remove(fault_dir / "capture.mp4"); std::filesystem::remove(fault_dir);
  const auto empty_dir = CreatePrivateCaptureDirectory();
  auto empty = ScriptMediaEncoder::Create(empty_dir, {"gif", "mp4"}, 10, 1048576);
  assert(empty->Finish(1).empty() && empty->finalization_failed());
  std::filesystem::remove(empty_dir);
  for (const auto& output : outputs) std::filesystem::remove(output.path);
  for (const auto& output : partial) std::filesystem::remove(output.path);
  std::filesystem::remove(directory); std::filesystem::remove(limited_dir);
  std::cout << report.dump(2) << std::endl;
}
