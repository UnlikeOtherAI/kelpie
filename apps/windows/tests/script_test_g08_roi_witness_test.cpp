#include "../../../native/engine-chromium-desktop/src/desktop_test_g08_scope.h"
#include "script_test_g08_roi_witness.h"
#include <cassert>
#include <cstdlib>

using namespace kelpie::windows;
int main() {
  _putenv_s("KELPIE_TEST_G08_URL", "http://example.invalid/g08/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
  _putenv_s("KELPIE_TEST_G08_FIXTURE_PID", "1");
  _putenv_s("KELPIE_TEST_G08_FIXTURE_EXE", "not-the-fixture");
  kelpie::TestG08Scope invalid_scope;
  assert(!invalid_scope.ListenerOwned() && !invalid_scope.MatchesUrl("http://example.invalid/"));
  ScriptMediaFrame frame{640, 406, 2560, std::vector<std::uint8_t>(640 * 406 * 4, 255), 123};
  TestG08RoiWitness witness;
  assert(witness.RecordAdmittedFrame(frame));
  frame.elapsed_ms += 50;
  assert(witness.RecordAdmittedFrame(frame));
  assert(witness.rows().size() == 2 && witness.rows()[0].pts100ns == 0 && witness.rows()[1].pts100ns == 500000);
  assert(witness.rows()[0].roi_sha256 == witness.rows()[1].roi_sha256);
  ScriptMediaOutput video; video.mime_type = "video/mp4"; video.width = 640; video.height = 406; video.frame_count = 2;
  assert(witness.Finalize(false, video));
  assert(!witness.Finalize(false, video));

  TestG08RoiWitness wrong_time;
  assert(wrong_time.RecordAdmittedFrame(frame));
  assert(!wrong_time.RecordAdmittedFrame(frame) && wrong_time.rows().empty());
  TestG08RoiWitness wrong_count;
  assert(wrong_count.RecordAdmittedFrame(frame));
  assert(!wrong_count.Finalize(false, video) && wrong_count.rows().empty());
  TestG08RoiWitness wrong_format;
  assert(wrong_format.RecordAdmittedFrame(frame));
  video.frame_count = 1; video.mime_type = "image/gif";
  assert(!wrong_format.Finalize(false, video));
}
