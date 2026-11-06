#pragma once
// Test-only helper. This does not establish fixture or owner identity: the
// sampler must supply that authority and keep it current before publication.
#if defined(KELPIE_TEST_G08_ROI_WITNESS)
#include "script_media_encoder.h"
#include <cstdint>
#include <string>
#include <vector>

namespace kelpie::windows {
struct TestG08RoiRow { std::size_t frame_index; std::int64_t pts100ns; std::string roi_sha256; };
class TestG08RoiWitness {
 public:
  // Only call after exact fixture, lease, grant, document and viewport fences.
  bool RecordAdmittedFrame(const ScriptMediaFrame& frame);
  void Invalidate() { valid_ = false; rows_.clear(); }
  // MP4-only: a completed FIFO writer with one retained sample per input and
  // no writer drops is necessary, but independent PTS verification is still
  // mandatory before these rows are evidence.
  bool Finalize(bool partial, const ScriptMediaOutput& output);
  const std::vector<TestG08RoiRow>& rows() const { return rows_; }
 private:
  bool valid_ = true, finalized_ = false;
  double origin_ms_ = 0;
  std::vector<TestG08RoiRow> rows_;
};
}  // namespace kelpie::windows
#endif
