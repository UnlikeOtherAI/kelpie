#include "desktop_script_result.h"
#include <cassert>

int main() {
  const nlohmann::json uncertain = {{"success",false},{"mayHaveCompleted",true},
    {"error",{{"code","SCRIPT_STOPPED"}}}};
  const auto capture = kelpie::ReplaceScriptErrorPreservingUncertainty(
    uncertain,"CAPTURE_EVIDENCE_TIMEOUT","Capture ended");
  assert(!capture.at("success").get<bool>());
  assert(capture.at("error").at("code") == "CAPTURE_EVIDENCE_TIMEOUT");
  assert(capture.at("mayHaveCompleted").get<bool>());
  const auto revoked = kelpie::ReplaceScriptErrorPreservingUncertainty(
    capture,"AUTHORIZATION_REVOKED","Grant ended");
  assert(revoked.at("error").at("code") == "AUTHORIZATION_REVOKED");
  assert(revoked.at("mayHaveCompleted").get<bool>());
  const auto safe = kelpie::ReplaceScriptErrorPreservingUncertainty(
    nlohmann::json{{"success",true}},"CAPTURE_FAILED","Capture ended");
  assert(!safe.contains("mayHaveCompleted"));
}
