#pragma once
#include <gst/app/gstappsrc.h>
#include <gst/app/gstappsink.h>
#include <nlohmann/json.hpp>

namespace kelpie::linuxapp::media {
// Fixed native element factories only. No page/model pipeline or file location.
void VerifyScriptGstPlugins();
nlohmann::json ScriptGstRuntimeInfo();
class GstPipeline {
 public:
  explicit GstPipeline(const char* fixed_description);
  ~GstPipeline();
  GstPipeline(const GstPipeline&) = delete;
  GstPipeline& operator=(const GstPipeline&) = delete;
  GstAppSrc* source() const { return GST_APP_SRC(source_); }
  GstAppSink* sink() const { return GST_APP_SINK(sink_); }
  void Start();
  void Push(GstBuffer* buffer); // Transfers ownership, also on a flow failure.
  GstSample* Pull();            // Caller owns the returned sample.
  bool Complete();             // Bounded EOS/error wait.
 private:
  void Clear();
  GstElement* pipeline_ = nullptr;
  GstElement* source_ = nullptr;
  GstElement* sink_ = nullptr;
  GstBus* bus_ = nullptr;
};
}
