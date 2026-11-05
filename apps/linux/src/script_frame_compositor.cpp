#include "script_frame_compositor.h"
#include "kelpie/script_presentation.h"
#include <cairo.h>
#include <openssl/evp.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <memory>
#include <stdexcept>

namespace kelpie::linuxapp {
namespace {
using Surface = std::unique_ptr<cairo_surface_t, decltype(&cairo_surface_destroy)>;
using Context = std::unique_ptr<cairo_t, decltype(&cairo_destroy)>;
struct Reader { const std::vector<std::uint8_t>& bytes; std::size_t offset = 0; };
cairo_status_t ReadPNG(void* raw, unsigned char* output, unsigned count) {
  auto& input = *static_cast<Reader*>(raw);
  if (count > input.bytes.size() - input.offset) return CAIRO_STATUS_READ_ERROR;
  std::memcpy(output, input.bytes.data() + input.offset, count); input.offset += count;
  return CAIRO_STATUS_SUCCESS;
}
cairo_status_t WritePNG(void* raw, const unsigned char* input, unsigned count) {
  auto& bytes = *static_cast<std::vector<std::uint8_t>*>(raw);
  if (count > 64 * 1024 * 1024 - bytes.size()) return CAIRO_STATUS_WRITE_ERROR;
  bytes.insert(bytes.end(), input, input + count); return CAIRO_STATUS_SUCCESS;
}
void Valid(const ScriptFrame& frame) {
  if (frame.width < 1 || frame.height < 1 || frame.width > 4096 || frame.height > 4096 ||
      std::uint64_t(frame.width) * frame.height > 8388608 || frame.stride != frame.width * 4 ||
      frame.bgra.size() != std::size_t(frame.stride) * frame.height)
    throw std::runtime_error("CAPTURE_FRAME_TOO_LARGE");
}
Surface FrameSurface(const ScriptFrame& frame) {
  Valid(frame);
  Surface surface(cairo_image_surface_create_for_data(const_cast<unsigned char*>(frame.bgra.data()),
      CAIRO_FORMAT_ARGB32, frame.width, frame.height, frame.stride), cairo_surface_destroy);
  if (cairo_surface_status(surface.get()) != CAIRO_STATUS_SUCCESS) throw std::runtime_error("CAPTURE_OVERLAY_FAILED");
  return surface;
}
std::uint32_t Word(const std::uint8_t* p) {
  return (std::uint32_t(p[0]) << 24) | (std::uint32_t(p[1]) << 16) | (std::uint32_t(p[2]) << 8) | p[3];
}
}
ScriptFrame DecodeScriptFrame(const std::string& encoded, int max_width, double elapsed_ms) {
  if (encoded.empty() || encoded.size() > 67108864 || encoded.size() % 4 || max_width < 2 || max_width > 4096 ||
      !std::isfinite(elapsed_ms)) throw std::runtime_error("CAPTURE_DECODE_FAILED");
  std::vector<std::uint8_t> bytes(encoded.size() / 4 * 3);
  const int count = EVP_DecodeBlock(bytes.data(), reinterpret_cast<const unsigned char*>(encoded.data()), static_cast<int>(encoded.size()));
  if (count < 0) throw std::runtime_error("CAPTURE_DECODE_FAILED");
  const std::size_t padding = (encoded.back() == '=') + (encoded[encoded.size() - 2] == '=');
  if (std::size_t(count) < padding) throw std::runtime_error("CAPTURE_DECODE_FAILED");
  bytes.resize(std::size_t(count) - padding);
  constexpr std::array<std::uint8_t, 8> signature = {137,80,78,71,13,10,26,10};
  if (bytes.size() < 33 || !std::equal(signature.begin(), signature.end(), bytes.begin()) ||
      Word(bytes.data() + 8) != 13 || std::memcmp(bytes.data() + 12, "IHDR", 4))
    throw std::runtime_error("CAPTURE_DECODE_FAILED");
  const auto width = Word(bytes.data() + 16), height = Word(bytes.data() + 20);
  // Check IHDR before Cairo can allocate storage for an untrusted compressed PNG.
  if (!width || !height || width > 16384 || height > 16384 || std::uint64_t(width) * height > 8388608)
    throw std::runtime_error("CAPTURE_FRAME_TOO_LARGE");
  Reader reader{bytes};
  Surface source(cairo_image_surface_create_from_png_stream(ReadPNG, &reader), cairo_surface_destroy);
  if (cairo_surface_status(source.get()) != CAIRO_STATUS_SUCCESS ||
      cairo_image_surface_get_width(source.get()) != int(width) || cairo_image_surface_get_height(source.get()) != int(height))
    throw std::runtime_error("CAPTURE_DECODE_FAILED");
  const double scale = std::min({1.0, double(max_width) / width, 1920.0 / height});
  if (width * scale < 2 || height * scale < 2) throw std::runtime_error("CAPTURE_VIEWPORT_UNSUPPORTED");
  ScriptFrame frame;
  frame.width = std::max(2, int(width * scale) / 2 * 2); frame.height = std::max(2, int(height * scale) / 2 * 2);
  frame.stride = frame.width * 4; frame.elapsed_ms = elapsed_ms;
  frame.bgra.resize(std::size_t(frame.stride) * frame.height);
  auto surface = FrameSurface(frame); Context cr(cairo_create(surface.get()), cairo_destroy);
  cairo_set_source_rgb(cr.get(), 1, 1, 1); cairo_paint(cr.get());
  cairo_scale(cr.get(), double(frame.width) / width, double(frame.height) / height);
  cairo_set_source_surface(cr.get(), source.get(), 0, 0);
  cairo_pattern_set_filter(cairo_get_source(cr.get()), CAIRO_FILTER_BEST); cairo_paint(cr.get());
  if (cairo_status(cr.get()) != CAIRO_STATUS_SUCCESS) throw std::runtime_error("CAPTURE_DECODE_FAILED");
  cairo_surface_flush(surface.get()); return frame;
}
void DrawScriptOverlay(ScriptFrame& frame, const nlohmann::json& shown) {
  auto surface = FrameSurface(frame); Context cr(cairo_create(surface.get()), cairo_destroy);
  const double width = std::max(1.0, shown.value("viewportWidth", double(frame.width)));
  const double height = std::max(1.0, shown.value("viewportHeight", double(frame.height)));
  cairo_scale(cr.get(), frame.width / width, frame.height / height);
  const double elapsed = shown.value("elapsedMs", frame.elapsed_ms);
  if (shown.contains("pointer")) {
    const auto& p = shown["pointer"]; const double x = p.value("x", 0.0), y = p.value("y", 0.0);
    cairo_move_to(cr.get(), x, y); cairo_line_to(cr.get(), x + 5, y + 19);
    cairo_line_to(cr.get(), x + 10, y + 12); cairo_line_to(cr.get(), x + 18, y + 10); cairo_close_path(cr.get());
    cairo_set_source_rgb(cr.get(), 1, 1, 1); cairo_fill_preserve(cr.get());
    cairo_set_source_rgb(cr.get(), 0, 0, 0); cairo_set_line_width(cr.get(), 1.5); cairo_stroke(cr.get());
  }
  if (shown.contains("marker")) {
    const auto& marker = shown["marker"];
    const double progress = (elapsed - marker.value("startedMs", elapsed)) / std::max(1.0, marker.value("durationMs", 700.0));
    if (progress >= 0 && progress < 1) {
      const auto state = kelpie_script_tap_presentation(progress, marker.value("wobble", true), marker.value("fade", true));
      unsigned long color = 0x3B82F6;
      try { color = std::stoul(marker.value("color", std::string("#3B82F6")).substr(1), nullptr, 16); } catch (...) {}
      cairo_set_source_rgba(cr.get(), ((color >> 16) & 255) / 255.0, ((color >> 8) & 255) / 255.0,
                           (color & 255) / 255.0, 178.0 / 255 * state.alpha);
      cairo_arc(cr.get(), marker.value("x", 0.0), marker.value("y", 0.0),
                std::clamp(marker.value("radius", 20.0), 1.0, 200.0) * state.scale, 0, 2 * std::acos(-1));
      cairo_fill(cr.get());
    }
  }
  if (shown.contains("commentary")) {
    const auto& note = shown["commentary"];
    if (elapsed - note.value("startedMs", elapsed) < note.value("durationMs", 3000.0)) {
      const auto text = note.value("text", std::string());
      const auto position = note.value("position", std::string("bottom"));
      const double top = position == "top" ? 24 : position == "center" ? height / 2 - 30 : height - 84;
      const double box_width = std::min(400.0, std::max(1.0, width - 16)), left = (width - box_width) / 2;
      cairo_rectangle(cr.get(), left, top, box_width, 60); cairo_set_source_rgba(cr.get(), 0, 0, 0, .71); cairo_fill(cr.get());
      cairo_save(cr.get()); cairo_rectangle(cr.get(), left + 8, top, box_width - 16, 60); cairo_clip(cr.get());
      cairo_select_font_face(cr.get(), "sans", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL); cairo_set_font_size(cr.get(), 15);
      cairo_text_extents_t metrics{}; cairo_text_extents(cr.get(), text.c_str(), &metrics);
      cairo_set_source_rgb(cr.get(), 1, 1, 1); cairo_move_to(cr.get(), width / 2 - metrics.width / 2 - metrics.x_bearing, top + 35);
      cairo_show_text(cr.get(), text.c_str()); cairo_restore(cr.get());
    }
  }
  if (cairo_status(cr.get()) != CAIRO_STATUS_SUCCESS) throw std::runtime_error("CAPTURE_OVERLAY_FAILED");
  cairo_surface_flush(surface.get());
}
std::vector<std::uint8_t> EncodeScriptPNG(const ScriptFrame& frame) {
  auto surface = FrameSurface(frame); std::vector<std::uint8_t> bytes;
  if (cairo_surface_write_to_png_stream(surface.get(), WritePNG, &bytes) != CAIRO_STATUS_SUCCESS)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  return bytes;
}
}
