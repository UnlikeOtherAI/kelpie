import assert from "node:assert/strict";

// Resolve the synthetic fixture by its unique URL, not by the worker's own UUID.
export function fixtureIdentity(targets, fixtureUrl) {
  assert.ok(Array.isArray(targets) && targets.length <= 256 && targets.every(item =>
    item && typeof item.targetId === "string" && item.targetId.length > 0 &&
    (item.browserContextId === undefined || typeof item.browserContextId === "string")), "TARGET_LIST_INVALID");
  const matches = targets.filter(item => item?.type === "page" && item.url === fixtureUrl);
  assert.equal(matches.length, 1, "FIXTURE_TARGET_NOT_UNIQUE");
  const {targetId,browserContextId} = matches[0];
  assert.ok(typeof targetId === "string" && targetId.length > 0 && targetId.length <= 512, "TARGET_ID_INVALID");
  assert.ok(typeof browserContextId === "string" && browserContextId.length > 0 && browserContextId.length <= 512,
    "CONTEXT_ID_UNAVAILABLE");
  return {targetId,browserContextId};
}
export function fixtureWasDisposed(targets, contextIds, identity) {
  assert.ok(Array.isArray(targets) && targets.length <= 256 && targets.every(item =>
    item && typeof item.targetId === "string" && item.targetId.length > 0 &&
    (item.browserContextId === undefined || typeof item.browserContextId === "string")), "TARGET_LIST_INVALID");
  assert.ok(Array.isArray(contextIds) && contextIds.length <= 256 && contextIds.every(id => typeof id === "string"),
    "CONTEXT_LIST_INVALID");
  assert.ok(identity && typeof identity.targetId === "string" && identity.targetId.length &&
    typeof identity.browserContextId === "string" && identity.browserContextId.length, "IDENTITY_INVALID");
  return !targets.some(item => item?.targetId === identity.targetId ||
    item?.browserContextId === identity.browserContextId) && !contextIds.includes(identity.browserContextId);
}
