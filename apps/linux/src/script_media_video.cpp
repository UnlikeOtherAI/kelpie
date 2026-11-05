#include "script_media_internal.h"
#ifdef KELPIE_LINUX_CODEC_FORCE_TEST
#include <gst/video/video-event.h>
#include <chrono>
#include <cstdio>
#endif
#include "script_artifact_store.h"
#include "script_gstreamer.h"
#include <algorithm>
#include <cmath>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace kelpie::linuxapp::media {
namespace {
struct BufferDelete { void operator()(GstBuffer* value) const { if (value) gst_buffer_unref(value); } };
struct SampleDelete { void operator()(GstSample* value) const { if (value) gst_sample_unref(value); } };
using Buffer = std::unique_ptr<GstBuffer, BufferDelete>;
using Sample = std::unique_ptr<GstSample, SampleDelete>;
// qtmux faststart requires a seekable private spool. Its bytes are a subset of
// the encoded packets already reserved in Budget. Never unlink a replaced file.
class MuxScratch {
 public:
  explicit MuxScratch(const std::filesystem::path& directory) {
    path_ = (directory / ".mux-XXXXXX").string();
    fd_ = mkstemp(path_.data());
    if (fd_ < 0) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
    struct stat info{};
    if (fcntl(fd_, F_SETFD, FD_CLOEXEC) || fchmod(fd_, 0600) || fstat(fd_, &info)) {
      close(fd_); unlink(path_.c_str()); throw std::runtime_error("CAPTURE_STORAGE_FAILED");
    }
    device_ = info.st_dev; inode_ = info.st_ino;
  }
  ~MuxScratch() { Remove(); }
  const std::string& path() const { return path_; }
  bool Remove() {
    if (fd_ < 0) return true;
    close(fd_); fd_ = -1;
    struct stat info{};
    if (lstat(path_.c_str(), &info)) return errno == ENOENT;
    if (!S_ISREG(info.st_mode) || info.st_dev != device_ || info.st_ino != inode_) return false;
    return unlink(path_.c_str()) == 0 || errno == ENOENT;
  }
 private:
  std::string path_;
  int fd_ = -1;
  dev_t device_{}; ino_t inode_{};
};
struct MuxState {
  std::mutex mutex;
  std::vector<std::uint8_t> bytes;
  std::size_t limit;
  bool overflow = false, failed = false;
  explicit MuxState(std::size_t maximum) : limit(maximum) {}
};
struct MuxResult { std::vector<std::uint8_t> bytes; bool overflow = false; };
GstFlowReturn Collect(GstAppSink* sink, gpointer raw) {
  auto& state = *static_cast<MuxState*>(raw);
  Sample sample(gst_app_sink_pull_sample(sink));
  std::lock_guard lock(state.mutex);
  auto* buffer = sample ? gst_sample_get_buffer(sample.get()) : nullptr;
  GstMapInfo mapped{};
  if (!buffer || !gst_buffer_map(buffer, &mapped, GST_MAP_READ)) { state.failed = true; return GST_FLOW_ERROR; }
  GstFlowReturn result = GST_FLOW_OK;
  if (mapped.size > state.limit - state.bytes.size()) { state.overflow = true; result = GST_FLOW_ERROR; }
  else {
    try { state.bytes.insert(state.bytes.end(), mapped.data, mapped.data + mapped.size); }
    catch (...) { state.failed = true; result = GST_FLOW_ERROR; }
  }
  gst_buffer_unmap(buffer, &mapped); return result;
}

bool ContainsVclAccessUnit(GstBuffer* packet, GstCaps* caps) {
  // AVC buffers can contain codec headers without a picture. Only a complete
  // length-prefixed access unit with an actual VCL NAL is source-frame evidence.
  const auto* value = gst_structure_get_value(gst_caps_get_structure(caps, 0), "codec_data");
  if (!value || !GST_VALUE_HOLDS_BUFFER(value)) return false;
  auto* description = gst_value_get_buffer(value);
  GstMapInfo config{}, encoded{};
  if (!description || !gst_buffer_map(description, &config, GST_MAP_READ)) return false;
  if (!gst_buffer_map(packet, &encoded, GST_MAP_READ)) { gst_buffer_unmap(description, &config); return false; }
  bool valid = config.size >= 7 && config.data[0] == 1, picture = false;
  const std::size_t length_bytes = valid ? (config.data[4] & 3) + 1 : 0;
  std::size_t offset = 0;
  while (valid && offset < encoded.size) {
    if (length_bytes > encoded.size - offset) { valid = false; break; }
    std::size_t length = 0;
    for (std::size_t index = 0; index < length_bytes; ++index) length = (length << 8) | encoded.data[offset++];
    if (!length || length > encoded.size - offset || (encoded.data[offset] & 0x80)) { valid = false; break; }
    const auto type = encoded.data[offset] & 31;
    picture = picture || (type >= 1 && type <= 5);
    offset += length;
  }
  gst_buffer_unmap(packet, &encoded); gst_buffer_unmap(description, &config);
  return valid && picture && offset == encoded.size;
}
class Video final : public Writer {
 public:
  Video(std::filesystem::path path, Budget& budget, int fps) : budget_(budget), fps_(fps) {
    VerifyScriptGstPlugins(); // Exact factories/license metadata, no automatic codec fallback.
    output_.path = std::move(path); output_.mime_type = "video/mp4";
  }
  ~Video() override { encoder_.reset(); if (caps_) gst_caps_unref(caps_); }
  void Prepare(const ScriptFrame& input) override {
    if (encoder_) return;
    if (!budget_.Take(65536)) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
    reserved_ = 65536;
    encoder_ = std::make_unique<GstPipeline>(
        "appsrc name=input format=time is-live=false block=false max-bytes=67108864 ! "
        "videoconvert ! video/x-raw,format=I420 ! "
        "openh264enc multi-thread=1 enable-frame-skip=false complexity=low usage-type=screen ! "
        "h264parse ! video/x-h264,stream-format=avc,alignment=au ! "
        "appsink name=output sync=false async=false max-buffers=2");
    auto* raw_caps = gst_caps_new_simple("video/x-raw", "format", G_TYPE_STRING, "BGRA",
        "width", G_TYPE_INT, input.width, "height", G_TYPE_INT, input.height,
        "framerate", GST_TYPE_FRACTION, fps_, 1, nullptr);
    if (!raw_caps) throw std::runtime_error("CAPTURE_VIDEO_UNAVAILABLE");
    gst_app_src_set_caps(encoder_->source(), raw_caps); gst_caps_unref(raw_caps); encoder_->Start();
    output_.width = input.width; output_.height = input.height;
    prepared_ = Encode(input, 0, GST_SECOND / fps_);
    if (!Admit(prepared_.get())) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
    // Prove actual first-frame encoding, AVC codec data and MP4 muxing before
    // the shared runtime can admit its first browser action.
    packets_.push_back(std::move(prepared_));
    try {
      auto proof = Mux(budget_.limit - budget_.used + reserved_);
      if (proof.overflow) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
    } catch (...) { prepared_ = std::move(packets_.back()); packets_.pop_back(); throw; }
    prepared_ = std::move(packets_.back()); packets_.pop_back();
  }
  bool Write(const ScriptFrame& input, double start_ms, double end_ms) override {
    if (finished_) throw std::runtime_error("CAPTURE_ALREADY_FINISHED");
    Prepare(input);
    if (stopped_) return false;
    const auto start = GstClockTime(std::llround(start_ms * GST_MSECOND));
    const auto end = GstClockTime(std::llround(end_ms * GST_MSECOND));
    Buffer packet;
    if (prepared_) {
      packet = std::move(prepared_);
      GST_BUFFER_PTS(packet.get()) = start; GST_BUFFER_DTS(packet.get()) = start;
      GST_BUFFER_DURATION(packet.get()) = std::max<GstClockTime>(1, end - start);
    } else {
      packet = Encode(input, start, std::max<GstClockTime>(1, end - start));
      if (!Admit(packet.get())) { stopped_ = true; ++output_.dropped_frames; return false; }
    }
    if (packets_.size() >= 36000) { budget_.exceeded = true; stopped_ = true; ++output_.dropped_frames; return false; }
    packets_.push_back(std::move(packet)); return true;
  }
  std::size_t CommittedSourceFrames() const override { return finished_ ? output_.frame_count : packets_.size(); }
  ScriptMediaOutput Finish() override {
    if (finished_) return output_;
    if (encoder_) {
      if (!encoder_->Complete()) throw std::runtime_error("CAPTURE_FINALIZE_FAILED");
      encoder_.reset();
    }
    prepared_.reset();
    // Encoded packets are bounded independently of container overhead. If muxer
    // overhead exceeds its reservation, remove complete tail packets and remux
    // only owned encoded data. Browser mutations are never retried.
    while (!packets_.empty()) {
      auto mux = Mux(budget_.limit - budget_.used + reserved_);
      if (!mux.overflow) {
        const auto* last = packets_.back().get();
        output_.duration_ms = double(GST_BUFFER_PTS(last) + GST_BUFFER_DURATION(last)) / GST_MSECOND;
        output_.frame_count = packets_.size();
        budget_.Release(reserved_); reserved_ = 0;
        if (!budget_.Take(mux.bytes.size())) throw std::runtime_error("CAPTURE_BUDGET_EXCEEDED");
        WriteCaptureFile(output_.path, mux.bytes); packets_.clear(); finished_ = true; return output_;
      }
      budget_.exceeded = true; ++output_.dropped_frames; packets_.pop_back();
    }
    budget_.Release(reserved_); reserved_ = 0; finished_ = true; return output_;
  }
 private:
  bool Admit(GstBuffer* packet) {
    const auto size = gst_buffer_get_size(packet);
    if (size > budget_.limit || !budget_.Take(size + 4096)) return false;
    reserved_ += size + 4096; return true;
  }
  Buffer Encode(const ScriptFrame& input, GstClockTime pts, GstClockTime duration) {
    Buffer raw(gst_buffer_new_allocate(nullptr, input.bgra.size(), nullptr));
    if (!raw || gst_buffer_fill(raw.get(), 0, input.bgra.data(), input.bgra.size()) != input.bgra.size())
      throw std::runtime_error("CAPTURE_ENCODING_FAILED");
    GST_BUFFER_PTS(raw.get()) = pts; GST_BUFFER_DTS(raw.get()) = pts; GST_BUFFER_DURATION(raw.get()) = duration;
#ifdef KELPIE_LINUX_CODEC_FORCE_TEST
    const auto index=encoded_test_index_++;
    if (index==14) {
      auto* sinkpad=gst_element_get_static_pad(GST_ELEMENT(encoder_->sink()),"sink");
      if (!sinkpad) throw std::runtime_error("CAPTURE_TEST_KEYFRAME_FAILED");
      const auto began=std::chrono::steady_clock::now();
      const bool accepted=gst_pad_push_event(sinkpad,gst_video_event_new_upstream_force_key_unit(
          GST_CLOCK_TIME_NONE,TRUE,0));
      gst_object_unref(sinkpad);
      const auto micros=std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now()-began).count();
      std::fprintf(stderr,"KELPIE_TEST_FORCE_KEYFRAME accepted=%d event_us=%lld\n",
          int(accepted),static_cast<long long>(micros));
      if (!accepted) throw std::runtime_error("CAPTURE_TEST_KEYFRAME_FAILED");
    }
#endif
    encoder_->Push(raw.release());
    Sample sample(encoder_->Pull());
    auto* sample_caps = gst_sample_get_caps(sample.get());
    auto* packet = gst_sample_get_buffer(sample.get());
    if (!sample_caps || !packet || !ContainsVclAccessUnit(packet, sample_caps))
      throw std::runtime_error("CAPTURE_ENCODING_FAILED");
#ifdef KELPIE_LINUX_CODEC_FORCE_TEST
    if (index==14 && GST_BUFFER_FLAG_IS_SET(packet,GST_BUFFER_FLAG_DELTA_UNIT))
      throw std::runtime_error("CAPTURE_TEST_KEYFRAME_NOT_EMITTED");
#endif
    if (!caps_) caps_ = gst_caps_ref(sample_caps);
    Buffer copied(gst_buffer_copy_deep(packet));
    if (!copied) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
    GST_BUFFER_PTS(copied.get()) = pts; GST_BUFFER_DTS(copied.get()) = pts; GST_BUFFER_DURATION(copied.get()) = duration;
    return copied;
  }
  MuxResult Mux(std::size_t limit) {
    MuxScratch scratch(output_.path.parent_path());
    MuxState state(limit);
    auto pipeline = std::make_unique<GstPipeline>(
        "appsrc name=input format=time is-live=false block=false max-bytes=268435456 ! "
        "video/x-h264,stream-format=avc,alignment=au ! "
        "mp4mux name=mux faststart=true trak-timescale=1000000 ! "
        "appsink name=output sync=false async=false max-buffers=2");
    pipeline->SetFastStartFile(scratch.path());
    gst_app_src_set_caps(pipeline->source(), caps_);
    GstAppSinkCallbacks callbacks{}; callbacks.new_sample = Collect;
    gst_app_sink_set_callbacks(pipeline->sink(), &callbacks, &state, nullptr);
    bool completed = false;
    try {
      pipeline->Start();
      for (const auto& packet : packets_) {
        auto* copy = gst_buffer_copy_deep(packet.get());
        if (!copy) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
        pipeline->Push(copy);
      }
      completed = pipeline->Complete();
    } catch (...) {
      pipeline.reset();
      if (!scratch.Remove()) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
      std::lock_guard lock(state.mutex);
      if (state.overflow) return {std::move(state.bytes), true};
      throw;
    }
    pipeline.reset(); // Join streaming callbacks before consuming their result.
    if (!scratch.Remove()) throw std::runtime_error("CAPTURE_STORAGE_FAILED");
    std::lock_guard lock(state.mutex);
    if (state.failed || (!completed && !state.overflow)) throw std::runtime_error("CAPTURE_ENCODING_FAILED");
    return {std::move(state.bytes), state.overflow};
  }
  Budget& budget_;
  int fps_;
  ScriptMediaOutput output_;
  std::unique_ptr<GstPipeline> encoder_;
  GstCaps* caps_ = nullptr;
  Buffer prepared_;
  std::vector<Buffer> packets_;
  std::size_t reserved_ = 0;
  bool finished_ = false, stopped_ = false;
#ifdef KELPIE_LINUX_CODEC_FORCE_TEST
  std::size_t encoded_test_index_=0;
#endif
};
}
std::unique_ptr<Writer> MakeVideo(const std::filesystem::path& path, Budget& budget, int fps) {
  return std::make_unique<Video>(path, budget, fps);
}
}
