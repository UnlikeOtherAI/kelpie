import assert from "node:assert/strict";
import { createHash } from "node:crypto";

// The reviewed manifest is supplied independently; do not infer its provenance.
export function verifyGtkDiagnosticManifest(bytes, expectedManifestSHA256, expectedSource, expectedBinarySHA256) {
  assert.ok(Buffer.isBuffer(bytes) && bytes.length > 0 && bytes.length <= 16384);
  assert.match(expectedManifestSHA256 ?? "", /^[a-f0-9]{64}$/);
  assert.match(expectedSource ?? "", /^[a-f0-9]{40}$/);
  const hash = createHash("sha256").update(bytes).digest("hex");
  assert.equal(hash, expectedManifestSHA256);
  const value = JSON.parse(bytes.toString("utf8"));
  assert.equal(value.historicalBase, "c42fc68d7fdfa01fae0cbe9cda82dc39bd8c4dc2");
  assert.equal(value.source, expectedSource);
  assert.equal(value.target, "kelpie-linux");
  assert.equal(value.binarySHA256, expectedBinarySHA256);
  assert.deepEqual(value.options, { BUILD_TESTING: true, CEF: true, GTK: true, STARTUP_TEST_TRACE: true });
  return { historicalBase: value.historicalBase, diagnosticBuildSource: value.source,
    diagnosticTarget: value.target, diagnosticManifestSHA256: hash };
}
