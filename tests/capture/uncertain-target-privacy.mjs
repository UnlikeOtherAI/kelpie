import assert from "node:assert/strict";

// The uncertainty oracle deliberately makes no zero-input or unchanged-value claim.
export function assertUncertainTargetPrivacy({ result, status }, { secret, expectedCode, expectedMayHaveCompleted = true }) {
  assert.ok(typeof secret === "string" && secret.length);
  assert.ok(typeof expectedCode === "string" && expectedCode.length);
  assert.equal(result.success, false);
  assert.equal(result.error?.code, expectedCode, "First concrete failure must survive privacy cleanup");
  assert.equal(result.mayHaveCompleted === true, expectedMayHaveCompleted, "Preserve actual input-completion uncertainty");
  assert.deepEqual(result.artifacts, [], "Uncertain target inspection cannot expose current media");
  assert.equal(status.success, true);
  assert.equal(status.playing, false, "Final metadata requires retired inspection");
  assert.equal(status.runSuccess, false);
  assert.equal(status.runError?.code, expectedCode);
  assert.deepEqual(status.artifacts, []);
  assert.ok(!Object.hasOwn(status, "outputs"));
  const serialized = JSON.stringify({ result, status });
  const percent = value => value.replace(/%[0-9a-f]{2}/gi, match => match.toUpperCase());
  const form = new URLSearchParams({ value: secret }).toString().slice(6);
  assert.ok(!serialized.includes(JSON.stringify(secret).slice(1, -1)), "Raw edit literal leaked");
  for (const encoded of [encodeURIComponent(secret), form])
    assert.ok(!percent(serialized).includes(percent(encoded)), "Encoded edit literal leaked");
  return { discarded: true, uncertaintyPreserved: true };
}

export function assertActiveArtifactPrivacy({ status, ownerDownload, foreignDownload, previousDownload }) {
  assert.equal(status.success, true);
  assert.equal(status.playing, true);
  assert.ok(["running", "finalizing"].includes(status.state));
  assert.deepEqual(status.artifacts, [], "Active current run must not publish captures");
  assert.equal(ownerDownload.error?.code, "ARTIFACT_NOT_READY");
  assert.equal(foreignDownload.error?.code, "ARTIFACT_NOT_FOUND");
  for (const response of [ownerDownload, foreignDownload])
    assert.ok(!Object.hasOwn(response, "data"), "Refused retrieval exposed bytes");
  assert.equal(previousDownload.success, true, "Prior safe run remains readable");
  return { currentHidden: true, previousReadable: true };
}
