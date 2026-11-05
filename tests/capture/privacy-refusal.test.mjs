import test from "node:test";
import assert from "node:assert/strict";
import { assertPrivacyRefusal } from "./privacy-refusal.mjs";

const secret = "Synthetic a+! private";
const evidence = () => ({
  result: { success: false, error: { code: "SENSITIVE_CAPTURE_REFUSED" }, outputs: { before: "[redacted]" }, artifacts: [] },
  status: { success: true, playing: false, state: "failed", runSuccess: false, artifacts: [] },
  editEvents: [], beforeValue: "", afterValue: "",
});
test("privacy refusal checks raw structured output, discarded media and no input", () => {
  assert.deepEqual(assertPrivacyRefusal(evidence(), { secret }), { privacyDiscard: true, noEdit: true });
  for (const reflected of [secret, encodeURIComponent(secret), new URLSearchParams({ value: secret }).toString().slice(6)]) {
    const leaked = evidence(); leaked.result.outputs.before = reflected.replace(/%[0-9A-F]{2}/g, value => value.toLowerCase());
    assert.throws(() => assertPrivacyRefusal(leaked, { secret }), /Sensitive value/);
  }
  for (const place of ["result", "status"]) {
    const retained = evidence(); retained[place].artifacts = [{ id: "old-capture" }];
    assert.throws(() => assertPrivacyRefusal(retained, { secret }), /discard|retain/);
  }
  const edit = evidence(); edit.editEvents.push({ type: "input" });
  assert.throws(() => assertPrivacyRefusal(edit, { secret }), /dispatch/);
});
test("later error replacement cannot authorize retained privacy captures", () => {
  const failed = evidence(); failed.result.error.code = "OUTPUT_REDACTION_FAILED";
  assertPrivacyRefusal(failed, { secret, expectedCode: "OUTPUT_REDACTION_FAILED" });
  failed.result.artifacts.push({ id: "earlier-safe-frame" });
  assert.throws(() => assertPrivacyRefusal(failed, { secret, expectedCode: "OUTPUT_REDACTION_FAILED" }), /discard/);
});
