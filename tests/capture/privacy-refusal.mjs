import assert from "node:assert/strict";

// Independent acceptance oracle; callers supply raw native responses, not host-scrubbed copies.
export function assertPrivacyRefusal(evidence, { secret, expectedCode = "SENSITIVE_CAPTURE_REFUSED" }) {
  assert.ok(typeof secret === "string" && secret.length, "Use a synthetic nonempty secret");
  const { result, status, editEvents, beforeValue, afterValue } = evidence;
  assert.equal(result.success, false, "Privacy refusal cannot report success");
  assert.equal(result.error?.code, expectedCode, "Unexpected refusal code");
  assert.deepEqual(result.artifacts, [], "Privacy refusal must discard every run artifact");
  assert.deepEqual(status.artifacts, [], "Status must not retain discarded artifact IDs");
  assert.equal(status.success, true, "Owner status query itself succeeds");
  assert.equal(status.playing, false, "Refused run must retire");
  assert.ok(!Object.hasOwn(status, "outputs"), "Status cannot expose outputs");
  assert.deepEqual(editEvents, [], "Refused edit cannot dispatch input");
  assert.equal(afterValue, beforeValue, "Refused edit changed the control");
  // Normalize only percent-triplet hex. Raw secret and ordinary letters remain case-sensitive.
  const percent = value => value.replace(/%[0-9a-f]{2}/gi, match => match.toUpperCase());
  const raw = JSON.stringify({ result, status });
  assert.ok(!raw.includes(JSON.stringify(secret).slice(1, -1)), "Sensitive value escaped raw native response");
  const serialized = percent(raw);
  const form = new URLSearchParams({ value: secret }).toString().slice("value=".length);
  for (const representation of [encodeURIComponent(secret), form])
    assert.ok(!serialized.includes(percent(representation)), "Sensitive value escaped raw native response");
  return { privacyDiscard: true, noEdit: true };
}
