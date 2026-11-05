#include "script_gstreamer.h"
#include <array>
#include <stdexcept>
#include <string>

namespace kelpie::linuxapp::media {
namespace {
constexpr std::array factories = {"appsrc", "appsink", "videoconvert", "openh264enc", "h264parse", "mp4mux"};
void Initialize() {
  GError* error = nullptr;
  if (!gst_init_check(nullptr, nullptr, &error)) {
    if (error) g_error_free(error);
    throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
  }
}
}
nlohmann::json ScriptGstRuntimeInfo() {
  Initialize();
  auto* version = gst_version_string();
  auto result = nlohmann::json{{"library", version ? version : ""}, {"plugins", nlohmann::json::array()}};
  g_free(version);
  for (const auto* name : factories) {
    auto* factory = gst_element_factory_find(name);
    if (!factory) throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
    auto* plugin = gst_plugin_feature_get_plugin(GST_PLUGIN_FEATURE(factory));
    gst_object_unref(factory);
    if (!plugin) throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
    const auto text = [](const char* value) { return std::string(value ? value : ""); };
    result["plugins"].push_back({{"factory", name}, {"name", text(gst_plugin_get_name(plugin))},
        {"version", text(gst_plugin_get_version(plugin))}, {"license", text(gst_plugin_get_license(plugin))},
        {"filename", text(gst_plugin_get_filename(plugin))}});
    gst_object_unref(plugin);
  }
  return result;
}
void VerifyScriptGstPlugins() {
  const auto info = ScriptGstRuntimeInfo();
  for (const auto& plugin : info["plugins"]) {
    const auto license = plugin["license"].get<std::string>();
    if (license != "LGPL" && license != "BSD" && license != "MIT")
      throw std::runtime_error("CAPTURE_CODEC_LICENSE_UNSUPPORTED");
  }
}
GstPipeline::GstPipeline(const char* description) {
  GError* error = nullptr;
  pipeline_ = gst_parse_launch(description, &error);
  if (error || !pipeline_) {
    if (error) g_error_free(error);
    Clear();
    throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
  }
  source_ = gst_bin_get_by_name(GST_BIN(pipeline_), "input");
  sink_ = gst_bin_get_by_name(GST_BIN(pipeline_), "output");
  bus_ = gst_element_get_bus(pipeline_);
  if (!source_ || !sink_ || !bus_) { Clear(); throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE"); }
}
GstPipeline::~GstPipeline() { Clear(); }
void GstPipeline::Clear() {
  if (pipeline_) gst_element_set_state(pipeline_, GST_STATE_NULL);
  if (source_) gst_object_unref(source_);
  if (sink_) gst_object_unref(sink_);
  if (bus_) gst_object_unref(bus_);
  if (pipeline_) gst_object_unref(pipeline_);
  pipeline_ = nullptr; source_ = nullptr; sink_ = nullptr; bus_ = nullptr;
}
void GstPipeline::SetFastStartFile(const std::string& path) {
  auto* mux = gst_bin_get_by_name(GST_BIN(pipeline_), "mux");
  if (!mux) throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
  const bool supported = g_object_class_find_property(G_OBJECT_GET_CLASS(mux), "faststart-file") != nullptr;
  if (supported) g_object_set(mux, "faststart-file", path.c_str(), nullptr);
  gst_object_unref(mux);
  if (!supported) throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
}
void GstPipeline::Start() {
  if (gst_element_set_state(pipeline_, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE)
    throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
}
void GstPipeline::Push(GstBuffer* buffer) {
  if (!buffer || gst_app_src_push_buffer(source(), buffer) != GST_FLOW_OK)
    throw std::runtime_error("CAPTURE_ENCODING_FAILED");
}
GstSample* GstPipeline::Pull() {
  auto* sample = gst_app_sink_try_pull_sample(sink(), 2 * GST_SECOND);
  if (!sample) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
  return sample;
}
bool GstPipeline::Complete() {
  if (gst_app_src_end_of_stream(source()) != GST_FLOW_OK) return false;
  auto* message = gst_bus_timed_pop_filtered(bus_, 5 * GST_SECOND,
      static_cast<GstMessageType>(GST_MESSAGE_EOS | GST_MESSAGE_ERROR));
  const bool completed = message && GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS;
  if (message) gst_message_unref(message);
  return completed;
}
}
