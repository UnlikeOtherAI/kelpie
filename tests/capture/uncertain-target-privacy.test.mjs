import test from "node:test";
import assert from "node:assert/strict";
import { assertUncertainTargetPrivacy, assertActiveArtifactPrivacy } from "./uncertain-target-privacy.mjs";
const secret = "Synthetic a+! late";
const options = { secret, expectedCode: "TARGET_TIMEOUT" };
const terminal = () => ({
  result: { success: false, error: { code: "TARGET_TIMEOUT" }, mayHaveCompleted: true, outputs: { before: "[redacted]" }, artifacts: [] },
  status: { success: true, playing: false, state: "failed", runSuccess: false, runError: { code: "TARGET_TIMEOUT" }, artifacts: [] },
});
test("lost classification preserves first error and uncertainty without claiming no edit", () => {
  assertUncertainTargetPrivacy(terminal(), options);
  for (const variant of [secret, encodeURIComponent(secret).replace(/%[0-9A-F]{2}/g, value => value.toLowerCase()), new URLSearchParams({ value: secret }).toString().slice(6)]) {
    const value = terminal(); value.result.outputs.before = variant;
    assert.throws(() => assertUncertainTargetPrivacy(value, options), /literal leaked/);
  }
  for (const field of ["result", "status"]) {
    const value = terminal(); value[field].artifacts.push({ id: "early-frame" });
    assert.throws(() => assertUncertainTargetPrivacy(value, options));
  }
  const changed = terminal(); changed.result.error.code = "SENSITIVE_CAPTURE_REFUSED";
  assert.throws(() => assertUncertainTargetPrivacy(changed, options), /First concrete/);
  const certain = terminal(); certain.result.mayHaveCompleted = false;
  assert.throws(() => assertUncertainTargetPrivacy(certain, options), /uncertain/);
});
test("running and finalizing withhold current media while prior safe run is readable", () => {
  for (const state of ["running", "finalizing"]) {
    const value = { status: { success: true, playing: true, state, artifacts: [] },
      ownerDownload: { error: { code: "ARTIFACT_NOT_READY" } },
      foreignDownload: { error: { code: "ARTIFACT_NOT_FOUND" } },
      previousDownload: { success: true } };
    assertActiveArtifactPrivacy(value);
    value.ownerDownload.data = "unexpected";
    assert.throws(() => assertActiveArtifactPrivacy(value), /exposed bytes/);
    delete value.ownerDownload.data;
    value.status.artifacts.push({ id: "early-frame" });
    assert.throws(() => assertActiveArtifactPrivacy(value), /publish/);
  }
});
