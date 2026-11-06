import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { verifyGtkDiagnosticManifest } from "./gtk-diagnostic-manifest.mjs";
const source = "1".repeat(40), binary = "2".repeat(64);
const input = { historicalBase: "c42fc68d7fdfa01fae0cbe9cda82dc39bd8c4dc2",
  source, target: "kelpie-linux", binarySHA256: binary,
  options: { BUILD_TESTING: true, CEF: true, GTK: true, STARTUP_TEST_TRACE: true } };
const bytes = value => Buffer.from(JSON.stringify(value));
const hash = value => createHash("sha256").update(value).digest("hex");
test("requires the exact reviewed manifest, build source, target and binary", () => {
  const data = bytes(input);
  assert.equal(verifyGtkDiagnosticManifest(data, hash(data), source, binary).diagnosticBuildSource, source);
  assert.throws(() => verifyGtkDiagnosticManifest(data, "0".repeat(64), source, binary));
  assert.throws(() => verifyGtkDiagnosticManifest(data, hash(data), "3".repeat(40), binary));
  assert.throws(() => verifyGtkDiagnosticManifest(data, hash(data), source, "4".repeat(64)));
  const other = bytes({ ...input, target: "other" });
  assert.throws(() => verifyGtkDiagnosticManifest(other, hash(other), source, binary));
});
test("rejects normal or incomplete options and oversized input", () => {
  const data = bytes({ ...input, options: { ...input.options, STARTUP_TEST_TRACE: false } });
  assert.throws(() => verifyGtkDiagnosticManifest(data, hash(data), source, binary));
  assert.throws(() => verifyGtkDiagnosticManifest(Buffer.alloc(16385), "0".repeat(64), source, binary));
});
