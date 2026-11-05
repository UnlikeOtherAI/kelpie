import assert from "node:assert/strict";
// Exact bounded RGB evidence only. A changed pixel is never silently forgiven.
export function sameG08Pixels(reference,candidate){
  assert.ok(Buffer.isBuffer(reference)&&Buffer.isBuffer(candidate));
  return reference.length===candidate.length&&reference.equals(candidate);
}
